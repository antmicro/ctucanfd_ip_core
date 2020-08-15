// SPDX-License-Identifier: GPL-2.0-or-later
/*******************************************************************************
 *
 * CTU CAN FD IP Core
 * Copyright (C) 2015-2018
 *
 * Authors:
 *     Ondrej Ille <ondrej.ille@gmail.com>
 *     Martin Jerabek <martin.jerabek01@gmail.com>
 *     Jaroslav Beran <jara.beran@gmail.com>
 *
 * Project advisors:
 *     Jiri Novak <jnovak@fel.cvut.cz>
 *     Pavel Pisa <pisa@cmp.felk.cvut.cz>
 *
 * Department of Measurement         (http://meas.fel.cvut.cz/)
 * Faculty of Electrical Engineering (http://www.fel.cvut.cz)
 * Czech Technical University        (http://www.cvut.cz/)
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 ******************************************************************************/

#include <linux/clk.h>
#include <linux/errno.h>
#include <linux/init.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/skbuff.h>
#include <linux/string.h>
#include <linux/types.h>
#include <linux/can/error.h>
#include <linux/can/led.h>
#include <linux/pm_runtime.h>

#include "ctu_can_fd.h"
#include "ctu_can_fd_regs.h"

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Martin Jerabek");
MODULE_DESCRIPTION("CTU CAN FD interface");

#define DRV_NAME "ctucanfd"

static const char * const ctucan_state_strings[] = {
	"CAN_STATE_ERROR_ACTIVE",
	"CAN_STATE_ERROR_WARNING",
	"CAN_STATE_ERROR_PASSIVE",
	"CAN_STATE_BUS_OFF",
	"CAN_STATE_STOPPED",
	"CAN_STATE_SLEEPING"
};

/* TX buffer rotation:
 * - when a buffer transitions to empty state, rotate order and priorities
 * - if more buffers seem to transition at the same time, rotate
 *   by the number of buffers
 * - it may be assumed that buffers transition to empty state in FIFO order
 *   (because we manage priorities that way)
 * - at frame filling, do not rotate anything, just increment buffer modulo
 *   counter
 */

#define CTUCAN_FLAG_RX_FFW_BUFFERED	1

static int ctucan_reset(struct net_device *ndev)
{
	int i;
	struct ctucan_priv *priv = netdev_priv(ndev);

	netdev_dbg(ndev, "ctucan_reset");

	ctucan_hw_reset(&priv->p);
	for (i = 0; i < 100; ++i) {
		if (ctucan_hw_check_access(&priv->p))
			return 0;
		usleep_range(100, 200);
	}

	netdev_warn(ndev, "device did not leave reset\n");
	return -ETIMEDOUT;
}

/**
 * ctucan_set_bittiming - CAN set bit timing routine
 * @ndev:	Pointer to net_device structure
 *
 * This is the driver set bittiming routine.
 * Return: 0 on success and failure value on error
 */
static int ctucan_set_bittiming(struct net_device *ndev)
{
	struct ctucan_priv *priv = netdev_priv(ndev);
	struct can_bittiming *bt = &priv->can.bittiming;

	netdev_dbg(ndev, "ctucan_set_bittiming");

	if (ctucan_hw_is_enabled(&priv->p)) {
		netdev_alert(ndev,
			     "BUG! Cannot set bittiming - CAN is enabled\n");
		return -EPERM;
	}

	/* Note that bt may be modified here */
	ctucan_hw_set_nom_bittiming(&priv->p, bt);

	return 0;
}

/**
 * ctucan_set_data_bittiming - CAN set data bit timing routine
 * @ndev:	Pointer to net_device structure
 *
 * This is the driver set data bittiming routine.
 * Return: 0 on success and failure value on error
 */
static int ctucan_set_data_bittiming(struct net_device *ndev)
{
	struct ctucan_priv *priv = netdev_priv(ndev);
	struct can_bittiming *dbt = &priv->can.data_bittiming;

	netdev_dbg(ndev, "ctucan_set_data_bittiming");

	if (ctucan_hw_is_enabled(&priv->p)) {
		netdev_alert(ndev,
			     "BUG! Cannot set bittiming - CAN is enabled\n");
		return -EPERM;
	}

	/* Note that dbt may be modified here */
	ctucan_hw_set_data_bittiming(&priv->p, dbt);

	return 0;
}

/**
 * ctucan_set_secondary_sample_point - CAN set secondary sample point routine
 * @ndev:	Pointer to net_device structure
 *
 * Return: 0 on success and failure value on error
 */
static int ctucan_set_secondary_sample_point(struct net_device *ndev)
{
	struct ctucan_priv *priv = netdev_priv(ndev);
	struct can_bittiming *dbt = &priv->can.data_bittiming;
	int ssp_offset = 0;
	bool ssp_ena;

	netdev_dbg(ndev, "ctucan_set_secondary_sample_point");

	if (ctucan_hw_is_enabled(&priv->p)) {
		netdev_alert(ndev,
			     "BUG! Cannot set SSP - CAN is enabled\n");
		return -EPERM;
	}

	// Use for bit-rates above 1 Mbits/s
	if (dbt->bitrate > 1000000) {
		ssp_ena = true;

		// Calculate SSP in minimal time quanta
		ssp_offset = (priv->can.clock.freq / 1000) *
			      dbt->sample_point / dbt->bitrate;

		if (ssp_offset > 127) {
			netdev_warn(ndev, "SSP offset saturated to 127\n");
			ssp_offset = 127;
		}
	} else {
		ssp_ena = false;
	}

	ctucan_hw_configure_ssp(&priv->p, ssp_ena, true, ssp_offset);

	return 0;
}

/**
 * ctucan_chip_start - This the drivers start routine
 * @ndev:	Pointer to net_device structure
 *
 * This is the drivers start routine.
 *
 * Return: 0 on success and failure value on error
 */
static int ctucan_chip_start(struct net_device *ndev)
{
	struct ctucan_priv *priv = netdev_priv(ndev);
	union ctu_can_fd_int_stat int_ena, int_msk;
	int err;
	struct can_ctrlmode mode;

	netdev_dbg(ndev, "ctucan_chip_start");

	err = ctucan_reset(ndev);
	if (err < 0)
		return err;

	priv->txb_prio = 0x01234567;
	priv->txb_head = 0;
	priv->txb_tail = 0;
	priv->p.write_reg(&priv->p, CTU_CAN_FD_TX_PRIORITY, priv->txb_prio);

	err = ctucan_set_bittiming(ndev);
	if (err < 0)
		return err;

	err = ctucan_set_data_bittiming(ndev);
	if (err < 0)
		return err;

	err = ctucan_set_secondary_sample_point(ndev);
	if (err < 0)
		return err;

	/* Enable interrupts */
	int_ena.u32 = 0;
	int_ena.s.rbnei = 1;
	int_ena.s.txbhci = 1;

	int_ena.s.ewli = 1;
	int_ena.s.fcsi = 1;

	mode.flags = priv->can.ctrlmode;
	mode.mask = 0xFFFFFFFF;
	ctucan_hw_set_mode_reg(&priv->p, &mode);

	/* One shot mode supported indirectly via Retransmit limit */
	if (priv->can.ctrlmode & CAN_CTRLMODE_ONE_SHOT)
		ctucan_hw_set_ret_limit(&priv->p, true, 0);

	/* Bus error reporting -> Allow Error interrupt */
	if (priv->can.ctrlmode & CAN_CTRLMODE_BERR_REPORTING) {
		int_ena.s.ali = 1;
		int_ena.s.bei = 1;
	}

	int_msk.u32 = ~int_ena.u32; /* mask all disabled interrupts */

	/* It's after reset, so there is no need to clear anything */
	ctucan_hw_int_mask_set(&priv->p, int_msk);
	ctucan_hw_int_ena_set(&priv->p, int_ena);

	/* Controller enters ERROR_ACTIVE on initial FCSI */
	priv->can.state = CAN_STATE_STOPPED;

	/* Enable the controller */
	ctucan_hw_enable(&priv->p, true);

	return 0;
}

/**
 * ctucan_do_set_mode - This sets the mode of the driver
 * @ndev:	Pointer to net_device structure
 * @mode:	Tells the mode of the driver
 *
 * This check the drivers state and calls the
 * the corresponding modes to set.
 *
 * Return: 0 on success and failure value on error
 */
static int ctucan_do_set_mode(struct net_device *ndev, enum can_mode mode)
{
	int ret;

	netdev_dbg(ndev, "ctucan_do_set_mode");

	switch (mode) {
	case CAN_MODE_START:
		ret = ctucan_chip_start(ndev);
		if (ret < 0) {
			netdev_err(ndev, "ctucan_chip_start failed!\n");
			return ret;
		}
		netif_wake_queue(ndev);
		break;
	default:
		ret = -EOPNOTSUPP;
		break;
	}

	return ret;
}

/**
 * ctucan_start_xmit - Starts the transmission
 * @skb:	sk_buff pointer that contains data to be Txed
 * @ndev:	Pointer to net_device structure
 *
 * This function is invoked from upper layers to initiate transmission. This
 * function uses the next available free txbuf and populates their fields to
 * start the transmission.
 *
 * Return: 0 on success and failure value on error
 */
static int ctucan_start_xmit(struct sk_buff *skb, struct net_device *ndev)
{
	struct ctucan_priv *priv = netdev_priv(ndev);
	struct net_device_stats *stats = &ndev->stats;
	struct canfd_frame *cf = (struct canfd_frame *)skb->data;
	u32 txb_id;
	bool ok;
	unsigned long flags;

	if (can_dropped_invalid_skb(ndev, skb))
		return NETDEV_TX_OK;

	/* Check if the TX buffer is full */
	if (unlikely(!CTU_CAN_FD_TXTNF(ctu_can_get_status(&priv->p)))) {
		netif_stop_queue(ndev);
		netdev_err(ndev, "BUG!, no TXB free when queue awake!\n");
		return NETDEV_TX_BUSY;
	}

	txb_id = priv->txb_head & priv->txb_mask;
	netdev_dbg(ndev, "%s: using TXB#%u", __func__, txb_id);
	ok = ctucan_hw_insert_frame(&priv->p, cf, 0, txb_id,
				    can_is_canfd_skb(skb));

	if (!ok) {
		netdev_err(ndev,
			   "BUG! TXNF set but cannot insert frame into TXTB! HW Bug?");
		return NETDEV_TX_BUSY;
	}
	can_put_echo_skb(skb, ndev, txb_id);

	if (!(cf->can_id & CAN_RTR_FLAG))
		stats->tx_bytes += cf->len;

	spin_lock_irqsave(&priv->tx_lock, flags);

	ctucan_hw_txt_set_rdy(&priv->p, txb_id);

	priv->txb_head++;

	/* Check if all TX buffers are full */
	if (!CTU_CAN_FD_TXTNF(ctu_can_get_status(&priv->p)))
		netif_stop_queue(ndev);

	spin_unlock_irqrestore(&priv->tx_lock, flags);

	return NETDEV_TX_OK;
}

/**
 * xcan_rx -  Is called from CAN isr to complete the received
 *		frame  processing
 * @ndev:	Pointer to net_device structure
 *
 * This function is invoked from the CAN isr(poll) to process the Rx frames. It
 * does minimal processing and invokes "netif_receive_skb" to complete further
 * processing.
 * Return: 1 on success and 0 on failure.
 */
static int ctucan_rx(struct net_device *ndev)
{
	struct ctucan_priv *priv = netdev_priv(ndev);
	struct net_device_stats *stats = &ndev->stats;
	struct canfd_frame *cf;
	struct sk_buff *skb;
	u64 ts;
	union ctu_can_fd_frame_form_w ffw;

	if (test_bit(CTUCAN_FLAG_RX_FFW_BUFFERED, &priv->drv_flags)) {
		ffw = priv->rxfrm_first_word;
		clear_bit(CTUCAN_FLAG_RX_FFW_BUFFERED, &priv->drv_flags);
	} else {
		ffw = ctu_can_fd_read_rx_ffw(&priv->p);
	}

	if (ffw.s.fdf == FD_CAN)
		skb = alloc_canfd_skb(ndev, &cf);
	else
		skb = alloc_can_skb(ndev, (struct can_frame **)&cf);

	if (unlikely(!skb)) {
		priv->rxfrm_first_word = ffw;
		set_bit(CTUCAN_FLAG_RX_FFW_BUFFERED, &priv->drv_flags);
		return 0;
	}

	ctucan_hw_read_rx_frame_ffw(&priv->p, cf, &ts, ffw);

	stats->rx_bytes += cf->len;
	stats->rx_packets++;
	netif_receive_skb(skb);

	return 1;
}

static const char *ctucan_state_to_str(enum can_state state)
{
	if (state >= CAN_STATE_MAX)
		return "UNKNOWN";
	return ctucan_state_strings[state];
}

/**
 * ctucan_err_interrupt - error frame Isr
 * @ndev:	net_device pointer
 * @isr:	interrupt status register value
 *
 * This is the CAN error interrupt and it will
 * check the the type of error and forward the error
 * frame to upper layers.
 */
static void ctucan_err_interrupt(struct net_device *ndev,
				 union ctu_can_fd_int_stat isr)
{
	struct ctucan_priv *priv = netdev_priv(ndev);
	struct net_device_stats *stats = &ndev->stats;
	struct can_frame *cf;
	struct sk_buff *skb;
	enum can_state state;
	struct can_berr_counter berr;
	union ctu_can_fd_err_capt_alc err_capt_alc;
	int dologerr = net_ratelimit();

	ctucan_hw_read_err_ctrs(&priv->p, &berr);
	state = ctucan_hw_read_error_state(&priv->p);
	err_capt_alc = ctu_can_fd_read_err_capt_alc(&priv->p);

	if (dologerr)
		netdev_info(ndev, "%s: ISR = 0x%08x, rxerr %d, txerr %d,"
			" error type %u, pos %u, ALC id_field %u, bit %u\n",
			__func__, isr.u32, berr.rxerr, berr.txerr,
			err_capt_alc.s.err_type, err_capt_alc.s.err_pos,
			err_capt_alc.s.alc_id_field, err_capt_alc.s.alc_bit);

	skb = alloc_can_err_skb(ndev, &cf);

	/* EWLI:  error warning limit condition met
	 * FCSI: Fault confinement State changed
	 * ALI:  arbitration lost (just informative)
	 * BEI:  bus error interrupt
	 */

	if (isr.s.fcsi || isr.s.ewli) {
		netdev_info(ndev, "  state changes from %s to %s",
			    ctucan_state_to_str(priv->can.state),
			    ctucan_state_to_str(state));

		if (priv->can.state == state)
			netdev_warn(ndev,
				    "current and previous state is the same! (missed interrupt?)");

		priv->can.state = state;
		if (state == CAN_STATE_BUS_OFF) {
			priv->can.can_stats.bus_off++;
			can_bus_off(ndev);
			if (skb)
				cf->can_id |= CAN_ERR_BUSOFF;
		} else if (state == CAN_STATE_ERROR_PASSIVE) {
			priv->can.can_stats.error_passive++;
			if (skb) {
				cf->can_id |= CAN_ERR_CRTL;
				cf->data[1] = (berr.rxerr > 127) ?
						CAN_ERR_CRTL_RX_PASSIVE :
						CAN_ERR_CRTL_TX_PASSIVE;
				cf->data[6] = berr.txerr;
				cf->data[7] = berr.rxerr;
			}
		} else if (state == CAN_STATE_ERROR_WARNING) {
			priv->can.can_stats.error_warning++;
			if (skb) {
				cf->can_id |= CAN_ERR_CRTL;
				cf->data[1] |= (berr.txerr > berr.rxerr) ?
					CAN_ERR_CRTL_TX_WARNING :
					CAN_ERR_CRTL_RX_WARNING;
				cf->data[6] = berr.txerr;
				cf->data[7] = berr.rxerr;
			}
		} else if (state == CAN_STATE_ERROR_ACTIVE) {
			cf->data[1] = CAN_ERR_CRTL_ACTIVE;
			cf->data[6] = berr.txerr;
			cf->data[7] = berr.rxerr;
		} else {
			netdev_warn(ndev, "    unhandled error state (%d:%s)!",
				    state, ctucan_state_to_str(state));
		}
	}

	/* Check for Arbitration Lost interrupt */
	if (isr.s.ali) {
		if (dologerr)
			netdev_info(ndev, "  arbitration lost");
		priv->can.can_stats.arbitration_lost++;
		if (skb) {
			cf->can_id |= CAN_ERR_LOSTARB;
			cf->data[0] = CAN_ERR_LOSTARB_UNSPEC;
		}
	}

	/* Check for Bus Error interrupt */
	if (isr.s.bei) {
		netdev_info(ndev, "  bus error");
		priv->can.can_stats.bus_error++;
		stats->tx_errors++; // TODO: really?
		if (skb) {
			cf->can_id |= CAN_ERR_PROT | CAN_ERR_BUSERROR;
			cf->data[2] = CAN_ERR_PROT_UNSPEC;
			cf->data[3] = CAN_ERR_PROT_LOC_UNSPEC;
		}
	}

	if (skb) {
		stats->rx_packets++;
		stats->rx_bytes += cf->can_dlc;
		netif_rx(skb);
	}
}

/**
 * ctucan_rx_poll - Poll routine for rx packets (NAPI)
 * @napi:	napi structure pointer
 * @quota:	Max number of rx packets to be processed.
 *
 * This is the poll routine for rx part.
 * It will process the packets maximux quota value.
 *
 * Return: number of packets received
 */
static int ctucan_rx_poll(struct napi_struct *napi, int quota)
{
	struct net_device *ndev = napi->dev;
	struct ctucan_priv *priv = netdev_priv(ndev);
	int work_done = 0;
	union ctu_can_fd_status status;
	u32 framecnt;

	framecnt = ctucan_hw_get_rx_frame_count(&priv->p);
	netdev_dbg(ndev, "rx_poll: %d frames in RX FIFO", framecnt);
	while (framecnt && work_done < quota) {
		ctucan_rx(ndev);
		work_done++;
		framecnt = ctucan_hw_get_rx_frame_count(&priv->p);
	}

	/* Check for RX FIFO Overflow */
	status = ctu_can_get_status(&priv->p);
	if (status.s.dor) {
		struct net_device_stats *stats = &ndev->stats;
		struct can_frame *cf;
		struct sk_buff *skb;

		netdev_info(ndev, "  rx fifo overflow");
		stats->rx_over_errors++;
		stats->rx_errors++;
		skb = alloc_can_err_skb(ndev, &cf);
		if (skb) {
			cf->can_id |= CAN_ERR_CRTL;
			cf->data[1] |= CAN_ERR_CRTL_RX_OVERFLOW;
			stats->rx_packets++;
			stats->rx_bytes += cf->can_dlc;
			netif_rx(skb);
		}

		/* Clear Data Overrun */
		ctucan_hw_clr_overrun_flag(&priv->p);
	}

	if (work_done)
		can_led_event(ndev, CAN_LED_EVENT_RX);

	if (!framecnt) {
		if (napi_complete_done(napi, work_done)) {
			union ctu_can_fd_int_stat iec;
			/* Clear and enable RBNEI. It is level-triggered, so
			 * there is no race condition.
			 */
			iec.u32 = 0;
			iec.s.rbnei = 1;
			ctucan_hw_int_clr(&priv->p, iec);
			ctucan_hw_int_mask_clr(&priv->p, iec);
		}
	}

	return work_done;
}

static void ctucan_rotate_txb_prio(struct net_device *ndev)
{
	struct ctucan_priv *priv = netdev_priv(ndev);
	u32 prio = priv->txb_prio;
	u32 nbuffersm1 = priv->txb_mask; /* nbuffers - 1 */

	prio = (prio << 4) | ((prio >> (nbuffersm1 * 4)) & 0xF);
	netdev_dbg(ndev, "%s: from 0x%08x to 0x%08x",
		   __func__, priv->txb_prio, prio);
	priv->txb_prio = prio;
	priv->p.write_reg(&priv->p, CTU_CAN_FD_TX_PRIORITY, prio);
}

/**
 * xcan_tx_interrupt - Tx Done Isr
 * @ndev:	net_device pointer
 */
static void ctucan_tx_interrupt(struct net_device *ndev)
{
	struct ctucan_priv *priv = netdev_priv(ndev);
	struct net_device_stats *stats = &ndev->stats;
	bool first = true;
	union ctu_can_fd_int_stat icr;
	bool some_buffers_processed;
	unsigned long flags;

	netdev_dbg(ndev, "%s", __func__);

	/*  read tx_status
	 *  if txb[n].finished (bit 2)
	 *	if ok -> echo
	 *	if error / aborted -> ?? (find how to handle oneshot mode)
	 *	txb_tail++
	 */

	icr.u32 = 0;
	icr.s.txbhci = 1;
	do {
		spin_lock_irqsave(&priv->tx_lock, flags);

		some_buffers_processed = false;
		while ((int)(priv->txb_head - priv->txb_tail) > 0) {
			u32 txb_idx = priv->txb_tail & priv->txb_mask;
			u32 status = ctucan_hw_get_tx_status(&priv->p, txb_idx);

			netdev_dbg(ndev, "TXI: TXB#%u: status 0x%x",
				   txb_idx, status);

			switch (status) {
			case TXT_TOK:
				netdev_dbg(ndev, "TXT_OK");
				can_get_echo_skb(ndev, txb_idx);
				stats->tx_packets++;
				break;
			case TXT_ERR:
				/* This indicated that retransmit limit has been
				 * reached. Obviously we should not echo the
				 * frame, but also not indicate any kind
				 * of error. If desired, it was already reported
				 * (possible multiple times) on each arbitration
				 * lost.
				 */
				netdev_warn(ndev, "TXB in Error state");
				can_free_echo_skb(ndev, txb_idx);
				stats->tx_dropped++;
				break;
			case TXT_ABT:
				/* Same as for TXT_ERR, only with different
				 * cause. We *could* re-queue the frame, but
				 * multiqueue/abort is not supported yet anyway.
				 */
				netdev_warn(ndev, "TXB in Aborted state");
				can_free_echo_skb(ndev, txb_idx);
				stats->tx_dropped++;
				break;
			default:
				/* Bug only if the first buffer is not finished,
				 * otherwise it is pretty much expected
				 */
				if (first) {
					netdev_err(ndev, "BUG: TXB#%u not in a finished state (0x%x)!",
						   txb_idx, status);
					spin_unlock_irqrestore(&priv->tx_lock,
							       flags);
					/* do not clear nor wake */
					return;
				}
				goto clear;
			}
			priv->txb_tail++;
			first = false;
			some_buffers_processed = true;
			/* Adjust priorities *before* marking the buffer
			 * as empty.
			 */
			ctucan_rotate_txb_prio(ndev);
			ctucan_hw_txt_set_empty(&priv->p, txb_idx);
		}
clear:
		spin_unlock_irqrestore(&priv->tx_lock, flags);

		/* If no buffers were processed this time, wa cannot
		 * clear - that would introduce a race condition.
		 */
		if (some_buffers_processed) {
			/* Clear the interrupt again as not to receive it again
			 * for a buffer we already handled (possibly causing
			 * the bug log)
			 */
			ctucan_hw_int_clr(&priv->p, icr);
		}
	} while (some_buffers_processed);

	can_led_event(ndev, CAN_LED_EVENT_TX);

	spin_lock_irqsave(&priv->tx_lock, flags);

	/* Check if at least one TX buffer is free */
	if (CTU_CAN_FD_TXTNF(ctu_can_get_status(&priv->p)))
		netif_wake_queue(ndev);

	spin_unlock_irqrestore(&priv->tx_lock, flags);
}

/**
 * xcan_interrupt - CAN Isr
 * @irq:	irq number
 * @dev_id:	device id poniter
 *
 * This is the CTU CAN FD ISR. It checks for the type of interrupt
 * and invokes the corresponding ISR.
 *
 * Return:
 * IRQ_NONE - If CAN device is in sleep mode, IRQ_HANDLED otherwise
 */
static irqreturn_t ctucan_interrupt(int irq, void *dev_id)
{
	struct net_device *ndev = (struct net_device *)dev_id;
	struct ctucan_priv *priv = netdev_priv(ndev);
	union ctu_can_fd_int_stat isr, icr;
	int irq_loops = 0;

	netdev_dbg(ndev, "ctucan_interrupt");

	do {
		/* Get the interrupt status */
		isr = ctu_can_fd_int_sts(&priv->p);

		if (!isr.u32)
			return irq_loops ? IRQ_HANDLED : IRQ_NONE;

		/* Receive Buffer Not Empty Interrupt */
		if (isr.s.rbnei) {
			netdev_dbg(ndev, "RXBNEI");
			icr.u32 = 0;
			icr.s.rbnei = 1;
			/* Mask RXBNEI the first then clear interrupt,
			 * then schedule NAPI. Even if another IRQ fires,
			 * isr.s.rbnei will always be 0 (masked).
			 */
			ctucan_hw_int_mask_set(&priv->p, icr);
			ctucan_hw_int_clr(&priv->p, icr);
			napi_schedule(&priv->napi);
		}

		/* TX Buffer HW Command Interrupt */
		if (isr.s.txbhci) {
			netdev_dbg(ndev, "TXBHCI");
			/* Cleared inside */
			ctucan_tx_interrupt(ndev);
		}

		/* Error interrupts */
		if (isr.s.ewli || isr.s.fcsi || isr.s.ali) {
			union ctu_can_fd_int_stat ierrmask = { .s = {
				  .ewli = 1, .fcsi = 1, .ali = 1, .bei = 1 } };
			icr.u32 = isr.u32 & ierrmask.u32;

			netdev_dbg(ndev, "some ERR interrupt: clearing 0x%08x",
				   icr.u32);
			ctucan_hw_int_clr(&priv->p, icr);
			ctucan_err_interrupt(ndev, isr);
		}
		/* Ignore RI, TI, LFI, RFI, BSI */
	} while (irq_loops++ < 10000);

	netdev_err(ndev, "%s: stuck interrupt (isr=0x%08x), stopping\n",
		   __func__, isr.u32);

	if (isr.s.txbhci) {
		int i;

		netdev_err(ndev, "txb_head=0x%08x txb_tail=0x%08x\n",
			   priv->txb_head, priv->txb_tail);
		for (i = 0; i <= priv->txb_mask; i++) {
			u32 status = ctucan_hw_get_tx_status(&priv->p, i);

			netdev_err(ndev, "txb[%d] txb status=0x%08x\n",
				   i, status);
		}
	}

	{
		union ctu_can_fd_int_stat imask;

		imask.u32 = 0xffffffff;
		ctucan_hw_int_ena_clr(&priv->p, imask);
		ctucan_hw_int_mask_set(&priv->p, imask);
	}

	return IRQ_HANDLED;
}

/**
 * ctucan_chip_stop - Driver stop routine
 * @ndev:	Pointer to net_device structure
 *
 * This is the drivers stop routine. It will disable the
 * interrupts and disable the controller.
 */
static void ctucan_chip_stop(struct net_device *ndev)
{
	struct ctucan_priv *priv = netdev_priv(ndev);
	union ctu_can_fd_int_stat mask;

	netdev_dbg(ndev, "ctucan_chip_stop");

	mask.u32 = 0xffffffff;

	/* Disable interrupts and disable can */
	ctucan_hw_int_mask_set(&priv->p, mask);
	ctucan_hw_enable(&priv->p, false);
	priv->can.state = CAN_STATE_STOPPED;
}

/**
 * ctucan_open - Driver open routine
 * @ndev:	Pointer to net_device structure
 *
 * This is the driver open routine.
 * Return: 0 on success and failure value on error
 */
static int ctucan_open(struct net_device *ndev)
{
	struct ctucan_priv *priv = netdev_priv(ndev);
	int ret;

	netdev_dbg(ndev, "ctucan_open");

	ret = pm_runtime_get_sync(priv->dev);
	if (ret < 0) {
		netdev_err(ndev, "%s: pm_runtime_get failed(%d)\n",
			   __func__, ret);
		return ret;
	}

	ret = request_irq(ndev->irq, ctucan_interrupt, priv->irq_flags,
			  ndev->name, ndev);
	if (ret < 0) {
		netdev_err(ndev, "irq allocation for CAN failed\n");
		goto err;
	}

	/* Common open */
	ret = open_candev(ndev);
	if (ret) {
		netdev_warn(ndev, "open_candev failed!\n");
		goto err_irq;
	}

	ret = ctucan_chip_start(ndev);
	if (ret < 0) {
		netdev_err(ndev, "ctucan_chip_start failed!\n");
		goto err_candev;
	}

	netdev_info(ndev, "ctu_can_fd device registered");
	can_led_event(ndev, CAN_LED_EVENT_OPEN);
	napi_enable(&priv->napi);
	netif_start_queue(ndev);

	return 0;

err_candev:
	close_candev(ndev);
err_irq:
	free_irq(ndev->irq, ndev);
err:
	pm_runtime_put(priv->dev);

	return ret;
}

/**
 * ctucan_close - Driver close routine
 * @ndev:	Pointer to net_device structure
 *
 * Return: 0 always
 */
static int ctucan_close(struct net_device *ndev)
{
	struct ctucan_priv *priv = netdev_priv(ndev);

	netdev_dbg(ndev, "ctucan_close");

	netif_stop_queue(ndev);
	napi_disable(&priv->napi);
	ctucan_chip_stop(ndev);
	free_irq(ndev->irq, ndev);
	close_candev(ndev);

	can_led_event(ndev, CAN_LED_EVENT_STOP);
	pm_runtime_put(priv->dev);

	return 0;
}

/**
 * ctucan_get_berr_counter - error counter routine
 * @ndev:	Pointer to net_device structure
 * @bec:	Pointer to can_berr_counter structure
 *
 * This is the driver error counter routine.
 * Return: 0 on success and failure value on error
 */
static int ctucan_get_berr_counter(const struct net_device *ndev,
				   struct can_berr_counter *bec)
{
	struct ctucan_priv *priv = netdev_priv(ndev);
	int ret;

	netdev_dbg(ndev, "ctucan_get_berr_counter");

	ret = pm_runtime_get_sync(priv->dev);
	if (ret < 0) {
		netdev_err(ndev, "%s: pm_runtime_get failed(%d)\n",
			   __func__, ret);
		return ret;
	}

	ctucan_hw_read_err_ctrs(&priv->p, bec);

	pm_runtime_put(priv->dev);

	return 0;
}

static const struct net_device_ops ctucan_netdev_ops = {
	.ndo_open	= ctucan_open,
	.ndo_stop	= ctucan_close,
	.ndo_start_xmit	= ctucan_start_xmit,
	.ndo_change_mtu	= can_change_mtu,
};

int ctucan_suspend(struct device *dev)
{
	struct net_device *ndev = dev_get_drvdata(dev);
	struct ctucan_priv *priv = netdev_priv(ndev);

	netdev_dbg(ndev, "ctucan_suspend");

	if (netif_running(ndev)) {
		netif_stop_queue(ndev);
		netif_device_detach(ndev);
	}

	priv->can.state = CAN_STATE_SLEEPING;

	return 0;
}
EXPORT_SYMBOL(ctucan_suspend);

int ctucan_resume(struct device *dev)
{
	struct net_device *ndev = dev_get_drvdata(dev);
	struct ctucan_priv *priv = netdev_priv(ndev);

	netdev_dbg(ndev, "ctucan_resume");

	priv->can.state = CAN_STATE_ERROR_ACTIVE;

	if (netif_running(ndev)) {
		netif_device_attach(ndev);
		netif_start_queue(ndev);
	}

	return 0;
}
EXPORT_SYMBOL(ctucan_resume);

int ctucan_probe_common(struct device *dev, void __iomem *addr,
			int irq, unsigned int ntxbufs, unsigned long can_clk_rate,
			int pm_enable_call, void (*set_drvdata_fnc)(struct device *dev,
			struct net_device *ndev))
{
	struct ctucan_priv *priv;
	struct net_device *ndev;
	int ret;

	/* Create a CAN device instance */
	ndev = alloc_candev(sizeof(struct ctucan_priv), ntxbufs);
	if (!ndev)
		return -ENOMEM;

	priv = netdev_priv(ndev);
	spin_lock_init(&priv->tx_lock);
	INIT_LIST_HEAD(&priv->peers_on_pdev);
	priv->txb_mask = ntxbufs - 1;
	priv->dev = dev;
	priv->can.bittiming_const = &ctu_can_fd_bit_timing_max;
	priv->can.data_bittiming_const = &ctu_can_fd_bit_timing_data_max;
	priv->can.do_set_mode = ctucan_do_set_mode;

	/* Needed for timing adjustment to be performed as soon as possible */
	priv->can.do_set_bittiming = ctucan_set_bittiming;
	priv->can.do_set_data_bittiming = ctucan_set_data_bittiming;

	priv->can.do_get_berr_counter = ctucan_get_berr_counter;
	priv->can.ctrlmode_supported = CAN_CTRLMODE_LOOPBACK
					| CAN_CTRLMODE_LISTENONLY
					| CAN_CTRLMODE_FD
					| CAN_CTRLMODE_PRESUME_ACK
					| CAN_CTRLMODE_BERR_REPORTING
					| CAN_CTRLMODE_FD_NON_ISO
					| CAN_CTRLMODE_ONE_SHOT;
	priv->p.mem_base = addr;

	/* Get IRQ for the device */
	ndev->irq = irq;
	ndev->flags |= IFF_ECHO;	/* We support local echo */

	if (set_drvdata_fnc != NULL)
		set_drvdata_fnc(dev, ndev);
	SET_NETDEV_DEV(ndev, dev);
	ndev->netdev_ops = &ctucan_netdev_ops;

	/* Getting the CAN can_clk info */
	if (can_clk_rate == 0) {
		priv->can_clk = devm_clk_get(dev, NULL);
		if (IS_ERR(priv->can_clk)) {
			dev_err(dev, "Device clock not found.\n");
			ret = PTR_ERR(priv->can_clk);
			goto err_free;
		}
		can_clk_rate = clk_get_rate(priv->can_clk);
	}

	priv->p.write_reg = ctucan_hw_write32;
	priv->p.read_reg = ctucan_hw_read32;

	if (pm_enable_call)
		pm_runtime_enable(dev);
	ret = pm_runtime_get_sync(dev);
	if (ret < 0) {
		netdev_err(ndev, "%s: pm_runtime_get failed(%d)\n",
			   __func__, ret);
		goto err_pmdisable;
	}

	if ((priv->p.read_reg(&priv->p, CTU_CAN_FD_DEVICE_ID) &
			    0xFFFF) != CTU_CAN_FD_ID) {
		priv->p.write_reg = ctucan_hw_write32_be;
		priv->p.read_reg = ctucan_hw_read32_be;
		if ((priv->p.read_reg(&priv->p, CTU_CAN_FD_DEVICE_ID) &
			      0xFFFF) != CTU_CAN_FD_ID) {
			netdev_err(ndev, "CTU_CAN_FD signature not found\n");
			ret = -ENODEV;
			goto err_disableclks;
		}
	}

	ret = ctucan_reset(ndev);
	if (ret < 0)
		goto err_pmdisable;

	priv->can.clock.freq = can_clk_rate;

	netif_napi_add(ndev, &priv->napi, ctucan_rx_poll, NAPI_POLL_WEIGHT);

	ret = register_candev(ndev);
	if (ret) {
		dev_err(dev, "fail to register failed (err=%d)\n", ret);
		goto err_disableclks;
	}

	devm_can_led_init(ndev);

	pm_runtime_put(dev);

	netdev_dbg(ndev, "mem_base=0x%p irq=%d clock=%d, txb mask:%d\n",
		   priv->p.mem_base, ndev->irq, priv->can.clock.freq,
		   priv->txb_mask);

	return 0;

err_disableclks:
	pm_runtime_put(priv->dev);
err_pmdisable:
	if (pm_enable_call)
		pm_runtime_disable(dev);
err_free:
	list_del_init(&priv->peers_on_pdev);
	free_candev(ndev);
	return ret;
}
EXPORT_SYMBOL(ctucan_probe_common);

static __init int ctucan_init(void)
{
	pr_info("%s CAN netdevice driver\n", DRV_NAME);

	return 0;
}

module_init(ctucan_init);

static __exit void ctucan_exit(void)
{
	pr_info("%s: driver removed\n", DRV_NAME);
}

module_exit(ctucan_exit);
