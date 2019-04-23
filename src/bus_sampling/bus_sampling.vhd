--------------------------------------------------------------------------------
-- 
-- CTU CAN FD IP Core
-- Copyright (C) 2015-2018
-- 
-- Authors:
--     Ondrej Ille <ondrej.ille@gmail.com>
--     Martin Jerabek <martin.jerabek01@gmail.com>
-- 
-- Project advisors: 
-- 	Jiri Novak <jnovak@fel.cvut.cz>
-- 	Pavel Pisa <pisa@cmp.felk.cvut.cz>
-- 
-- Department of Measurement         (http://meas.fel.cvut.cz/)
-- Faculty of Electrical Engineering (http://www.fel.cvut.cz)
-- Czech Technical University        (http://www.cvut.cz/)
-- 
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this VHDL component and associated documentation files (the "Component"),
-- to deal in the Component without restriction, including without limitation
-- the rights to use, copy, modify, merge, publish, distribute, sublicense,
-- and/or sell copies of the Component, and to permit persons to whom the
-- Component is furnished to do so, subject to the following conditions:
-- 
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Component.
-- 
-- THE COMPONENT IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHTHOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
-- FROM, OUT OF OR IN CONNECTION WITH THE COMPONENT OR THE USE OR OTHER DEALINGS
-- IN THE COMPONENT.
-- 
-- The CAN protocol is developed by Robert Bosch GmbH and protected by patents.
-- Anybody who wants to implement this IP core on silicon has to obtain a CAN
-- protocol license from Bosch.
-- 
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Purpose:
--  1. Implements Generic Synchronisation chain for incoming data
--  2. Detects appropriate edge for synchronisation!!
--  3. Measure Transciever delay compensation on command
--  4. Sample bus values in sample point of Bit time:
--    a) By normal sampling, at position of sample point (Transciever,reciever)
--    b) In secondary sample point for Transciever of CAN FD Data Phase
--  5. Detect bit Error by comparing transmitted values and Sampled values!
--
--Note: this bit error detection used in the end only for data phase transciever 
--      of CAN FD Phase! In other cases bit error is detected inside CAN-Core by
--      comparing transmitted and recieved bit.
--------------------------------------------------------------------------------
--    July 2015   Created file
--    19.12.2015  Added tripple sampling mode. Furthermore sampling is disabled
--                when whole controller is disabled
--    15.6.2016   1.edge_tx_valid signal now provides edge detection only from 
--                  RECESSIVE to DOMINANT values! In CAN FD standard EDL and r0
--                  bits are used for TRD measurment! When busSync is configured
--                  to start on TX edge and finish on RX edge.
--                2.Changed trv_delay size to cover mostly 127 clock cycles!
--                  Changed shift register sizes to 130 to avoid missing secon-
--                  dary sample signals!!
--                3.Fixed tripple sampling mode selection from three. Added 
--                  missing signals
--                4. trv_to_restart signal added to make it impossible to res-
--                   tart trv delay measurment without rising edge on trv_delay
--                   calib signal. This removes a bug when trv_delay_calib
--                   is forgottern active and circuit keeps measuring on every 
--                   edge...
--    27.6.2016   Bug fix. Transciever delay measurment conditions switched. Now
--                starting edge is the most prioritized logic. Thus transciever
--                delay counter is always erased with TX edge!
--                'elsif(edge_tx_valid='1')' swapped with 'if(trv_running='1')'.
--                Thisway if more TX edge would come before first RX edge is
--                sampled, shorter time would be measured! Note that this is OK
--                since in CAN spec. EDL bit is in nominal bit time and no other
--                edge can be transmitted before it is recieved (condition of 
--                original CAN)
--    20.4.2018   Added register to "trv_delay_out". Transceiver delay is
--                updated on the output only once the measurement has finished.
--                Thus reading TRV_DELAY register would always result in tran-
--                sceiver delay of last CAN FD Frame. This is done to avoid
--                reading wrong value from TRV_DELAY register during measurment.
--   10.12.2018   Re-factored, added generic Shift register instances. Added
--                generic synchronisation chain module.
--    16.1.2019   Replaced TX Data Shift register with FIFO like TX Data Cache.
--                TX Data are stored only once per bit. TX Data Cache consumes
--                drastically less DFFs. 
--------------------------------------------------------------------------------

Library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.ALL;

Library work;
use work.id_transfer.all;
use work.can_constants.all;
use work.can_components.all;
use work.can_types.all;
use work.cmn_lib.all;
use work.drv_stat_pkg.all;
use work.endian_swap.all;
use work.reduce_lib.all;

use work.CAN_FD_register_map.all;
use work.CAN_FD_frame_format.all;

entity bus_sampling is 
    generic(        
        -- Reset polarity
        G_RESET_POLARITY        :     std_logic := '0';
        
        -- Secondary sampling point Shift registers length
        G_SSP_SHIFT_LENGTH      :     natural := 130;

        -- Depth of FIFO Cache for TX Data
        G_TX_CACHE_DEPTH        :     natural := 8;
        
        -- Width (number of bits) in transceiver delay measurement counter
        G_TRV_CTR_WIDTH         :     natural := 7;
        
        -- Optional usage of saturated value of ssp_delay 
        G_USE_SSP_SATURATION    :     boolean := true
    );  
    port(
        ------------------------------------------------------------------------
        -- Clock and Async reset
        ------------------------------------------------------------------------
        -- System clock
        clk_sys              :in   std_logic;
        
        -- Asynchronous reset
        res_n                :in   std_logic;

        ------------------------------------------------------------------------
        --  Physical layer interface
        ------------------------------------------------------------------------
        -- CAN serial stream output
        CAN_rx               :in   std_logic;
        
        -- CAN serial stream input
        CAN_tx               :out  std_logic;

        ------------------------------------------------------------------------
        -- Memorz registers interface
        ------------------------------------------------------------------------
        -- Driving bus
        drv_bus              :in   std_logic_vector(1023 downto 0);
        
        -- Measured Transceiver delay output 
        trv_delay_out        :out  std_logic_vector(15 downto 0);
          
        ------------------------------------------------------------------------
        -- Prescaler interface
        ------------------------------------------------------------------------
        -- RX Trigger for Nominal Bit Time
        sample_nbt           :in   std_logic;

        -- RX Trigger for Data Bit Time
        sample_dbt           :in   std_logic;

        -- Valid synchronisation edge appeared (Recessive to Dominant)
        sync_edge            :out  std_logic;

        ------------------------------------------------------------------------
        -- CAN Core Interface
        ------------------------------------------------------------------------
        -- TX data
        data_tx              :in   std_logic;

        -- RX data
        data_rx              :out  std_logic;

        -- Sample control
        sp_control           :in   std_logic_vector(1 downto 0);
            
        -- Reset for Secondary Sampling point Shift register.
        ssp_reset            :in   std_logic;

        -- Calibration command for transciever delay compenstation
        trv_delay_calib      :in   std_logic; 

        -- Secondary sampling RX trigger
        sample_sec           :out  std_logic;

        -- Bit error detected
        bit_Error            :out  std_logic 
    );
end entity;

architecture rtl of bus_sampling is

    -----------------------------------------------------------------------------
    -- Internal constants declaration.
    -----------------------------------------------------------------------------
    -- Reset value for secondar sampling point shift registers
    constant C_SSP_SHIFT_RST_VAL : std_logic_vector(G_SSP_SHIFT_LENGTH - 1 downto 0) :=
                                    (OTHERS => '0');

    -- Saturation value of Secondary sampling point delay!
    constant C_SSP_DELAY_SAT_VAL : natural := G_SSP_SHIFT_LENGTH - 1; 

    -----------------------------------------------------------------------------
    -- Driving bus aliases
    -----------------------------------------------------------------------------

    -- Tripple sampling (as SJA1000)
    signal drv_sam              : std_logic;

    -- Enable of the whole driver
    signal drv_ena              : std_logic;

    -- Secondary sampling point offset.
    signal drv_ssp_offset       : std_logic_vector(6 downto 0);

    -- What value shall be used for ssp_delay (trv_delay, trv_delay+ssp_offset,
    -- ssp_offset)
    signal drv_ssp_delay_select : std_logic_vector(1 downto 0);

    -----------------------------------------------------------------------------
    -- Internal registers and signals
    -----------------------------------------------------------------------------

    -- CAN RX synchronisation chain output
    signal CAN_rx_synced        : std_logic;

    -- Internal received CAN Data. Selected between Raw input value and
    -- synchronised value by signal synchroniser.
    signal CAN_rx_i             : std_logic;

    -- Majority value from all three sampled values in tripple sampling shift 
    -- register
    signal CAN_rx_trs_majority  : std_logic; 

    -- CAN RX Data selected between normally sampled data (CAN_rx_i) and
    -- Tripple sampled data!
    signal data_rx_nbt          : std_logic;

    -- Bus sampling and edge detection, Previously sampled value on CAN bus
    signal prev_Sample          : std_logic;

    -- Secondary sampling signal (sampling with transciever delay compensation)
    signal sample_sec_i         : std_logic;
    signal sample_sec_comb      : std_logic;

    -- Delayed TX Data from TX Data shift register at position of secondary
    -- sampling point.
    signal data_tx_delayed      : std_logic;

    -- Shift Register for generating secondary sampling signal
    signal sample_sec_shift : std_logic_vector(G_SSP_SHIFT_LENGTH - 1 downto 0);

    -- Appropriate edge appeared at recieved data
    signal edge_rx_valid        : std_logic;

    -- Edge appeared at transcieved data
    signal edge_tx_valid        : std_logic;

    -- Tripple sampling shift register
    signal trs_reg              : std_logic_vector(2 downto 0);

    --Note: Bit Error is set up at sample point for whole bit 
    -- time until next sample point!!!!!
    
    -- SSP delay. Calculated from trv_delay either directly or by offseting
    -- by ssp_offset.
    signal ssp_delay            : std_logic_vector(7 downto 0);
    
    -- Measured transceived delay.
    signal trv_delay            : std_logic_vector(6 downto 0);

    ---------------------------------------------------------------------------
    -- Reset for shift registers. This is used instead of shift register with
    -- preload to lower the resource usage! Resetting and preloading to the
    -- same value can be merged into just resetting by OR of sources
    ---------------------------------------------------------------------------
    signal shift_regs_res_d     : std_logic;
    signal shift_regs_res_q     : std_logic;
    
    -- Enable for secondary sampling point shift register
    signal ssp_sr_ce            : std_logic;

begin
    
    ---------------------------------------------------------------------------
    -- Driving bus aliases
    ---------------------------------------------------------------------------
    drv_sam               <= drv_bus(DRV_SAM_INDEX);
    drv_ena               <= drv_bus(DRV_ENA_INDEX);

    drv_ssp_offset        <= drv_bus(DRV_SSP_OFFSET_HIGH downto
                                     DRV_SSP_OFFSET_LOW);
    drv_ssp_delay_select  <= drv_bus(DRV_SSP_DELAY_SELECT_HIGH downto
                                     DRV_SSP_DELAY_SELECT_LOW);

    ----------------------------------------------------------------------------
    -- Synchronisation chain for input signal
    ----------------------------------------------------------------------------
    can_rx_sig_sync_inst : sig_sync
    port map(
        clk     => clk_sys,
        async   => CAN_rx,
        sync    => CAN_rx_synced
    );

    ---------------------------------------------------------------------------
    -- Synchronisation-chain selection
    ---------------------------------------------------------------------------
    CAN_rx_i <= CAN_rx_synced;
    
    ---------------------------------------------------------------------------
    -- Component for measurement of transceiver delay and calculation of
    -- secondary sampling point.
    ---------------------------------------------------------------------------
    trv_delay_measurement_inst : trv_delay_measurement
    generic map(
        G_RESET_POLARITY         => G_RESET_POLARITY,
        G_TRV_CTR_WIDTH          => G_TRV_CTR_WIDTH,
        G_USE_SSP_SATURATION     => G_USE_SSP_SATURATION,
        G_SSP_SATURATION_LVL     => C_SSP_DELAY_SAT_VAL
    )
    port map(
        clk_sys                => clk_sys,                  -- IN
        res_n                  => res_n,                    -- IN

        meas_start             => edge_tx_valid,            -- IN
        meas_stop              => edge_rx_valid,            -- IN
        meas_enable            => trv_delay_calib,          -- IN
        ssp_offset             => drv_ssp_offset,           -- IN                    
        ssp_delay_select       => drv_ssp_delay_select,     -- IN
        
        trv_meas_progress      => open,                     -- OUT
        trv_delay_shadowed     => trv_delay,                -- OUT
        ssp_delay_shadowed     => ssp_delay                 -- OUT
    );

    
    ---------------------------------------------------------------------------
    -- Propagate measured transceiver delay to output so that it can be
    -- read from Memory registers.
    ---------------------------------------------------------------------------
    trv_delay_out(trv_delay_out'length - 1 downto trv_delay'length) <=
        (OTHERS => '0');
    trv_delay_out(trv_delay'length - 1 downto 0) <= trv_delay;


    ---------------------------------------------------------------------------
    -- Tripple sampling majority selection
    ---------------------------------------------------------------------------
    trs_maj_dec_inst : majority_decoder_3
    port map(
        input   => trs_reg,             -- IN
        
        output  => CAN_rx_trs_majority  -- OUT
    );


    ---------------------------------------------------------------------------
    -- Edge detector on TX, RX Data
    ---------------------------------------------------------------------------
    data_edge_detector_inst : data_edge_detector
    generic map(
        G_RESET_POLARITY    => G_RESET_POLARITY
    )
    port map(
        clk_sys             => clk_sys,         -- IN
        res_n               => res_n,           -- IN
        tx_data             => data_tx,         -- IN
        rx_data             => CAN_rx_i,        -- IN
        prev_rx_sample      => prev_sample,     -- IN
        
        tx_edge             => edge_tx_valid,   -- OUT
        rx_edge             => edge_rx_valid    -- OUT
    );


    ----------------------------------------------------------------------------
    -- Reset for shift registers for secondary sampling point
    ----------------------------------------------------------------------------
    shift_regs_res_d <= '1' when (res_n = G_RESET_POLARITY) or (ssp_reset = '1')
                            else
                        '0';

    ----------------------------------------------------------------------------
    -- Pipeline reset for shift registers to avoid glitches!
    ----------------------------------------------------------------------------
    shift_regs_rst_reg_inst : dff_arst
    generic map(
        reset_polarity     => G_RESET_POLARITY,
        rst_val            => '1'
    )
    port map(
        -- Keep without reset! We can't use res_n to avoid reset recovery!
        -- This does not mind, since stable value will be here one clock cycle
        -- after reset by res_n.
        arst               => '1',                  -- IN
        clk                => sys_clk,              -- IN

        input              => shift_regs_res_d,     -- IN
        load               => '0',                  -- IN
        
        output             => shift_regs_res_q      -- OUT
    );


    ----------------------------------------------------------------------------
    -- Shift register for secondary sampling point. Normal sample point trigger
    -- is shifted into shift register to generate delayed sampling point.
    ----------------------------------------------------------------------------
    ssp_shift_reg_inst : shift_reg
    generic map(
        G_RESET_POLARITY     => G_RESET_POLARITY,
        G_RESET_VALUE        => C_SSP_SHIFT_RST_VAL,
        G_WIDTH              => G_SSP_SHIFT_LENGTH,
        G_SHIFT_DOWN         => false
    )
    port map(
        clk                => clk_sys,              -- IN
        res_n              => shift_regs_res_q,     -- IN

        input              => sample_dbt,           -- IN
        enable             => ssp_sr_ce,            -- IN

        reg_stat           => sample_sec_shift,     -- OUT
        output             => open                  -- OUT
    );

    -- Secondary sampling point shift register clock enable
    ssp_sr_ce <= '1' when (sp_control = SECONDARY_SAMPLE) else
                 '0';

    ----------------------------------------------------------------------------
    -- Secondary sampling point address decoder. Secondary sampling point
    -- is taken from SSP Shift register at position of transceiver delay.
    ----------------------------------------------------------------------------
    sample_sec_comb <= sample_sec_shift(to_integer(unsigned(ssp_delay)));


    ----------------------------------------------------------------------------
    -- TX DATA Cache. Stores TX Data when Sample point enters the SSP shift
    -- register and reads data when Sample point steps out of shift register.
    -- This gets the TX data which correspond to the RX Bit in Secondary
    -- sampling point.
    ----------------------------------------------------------------------------
    tx_data_cache_inst : tx_data_cache
    generic map(
        G_RESET_POLARITY    => G_RESET_POLARITY,
        G_TX_CACHE_DEPTH    => G_TX_CACHE_DEPTH,
        G_TX_CACHE_RES_VAL  => RECESSIVE
    )
    port map(
        clk_sys           => clk_sys,               -- IN
        res_n             => shift_regs_res_q,      -- IN
        write             => sample_dbt,            -- IN
        read              => sample_sec,            -- IN
        data_in           => data_tx,               -- IN
        
        data_out          => data_tx_delayed        -- OUT
    );


    ----------------------------------------------------------------------------
    -- Registering secondary sampling point
    ----------------------------------------------------------------------------
    ssp_gen_proc : process(res_n, clk_sys)
    begin
        if (res_n = G_RESET_POLARITY) then
            sample_sec          <= '0';
            
        elsif rising_edge(clk_sys) then  
            if (ssp_reset = '1') then
                sample_sec_i        <= '0';
            else
                sample_sec_i        <= sample_sec_comb;
            end if;
        end if;
    end process;


    ----------------------------------------------------------------------------
    -- Separate process for tripple sampling with simple shift register. 
    -- Sampling is continous into shift register of lenth 3. If this option is 
    -- desired then majority out of whole shift register is selected as sampled
    -- value!
    ----------------------------------------------------------------------------
    trs_shift_reg_inst : shift_reg_preload
    generic map(
        G_RESET_POLARITY     => G_RESET_POLARITY,
        G_RESET_VALUE        => "000",
        G_WIDTH              => 3,
        G_SHIFT_DOWN         => false
    )
    port map(
        clk                => clk_sys,      -- IN
        res_n              => res_n,        -- IN
        
        input              => CAN_rx_i,     -- IN
        preload            => '0',          -- IN
        preload_val        => "000",        -- IN
        enable             => '1',          -- IN

        reg_stat           => trs_reg,      -- OUT
        output             => open          -- OUT
    );


    ---------------------------------------------------------------------------
    -- Selection of RX Data sampled in Nominal Bit-rate between Normally
    -- sampled and tripple sampled data.
    ---------------------------------------------------------------------------
    data_rx_nbt <= CAN_rx_trs_majority when (drv_sam = TSM_ENABLE) else
                   CAN_rx_i;

    ---------------------------------------------------------------------------
    -- Bit error detector
    ---------------------------------------------------------------------------
    bit_error_detector_inst : bit_error_detector
    generic map(
         G_RESET_POLARITY   => G_RESET_POLARITY
    )
    port map(
        clk_sys             => clk_sys,             -- IN
        res_n               => res_n,               -- IN
        drv_ena             => drv_ena,             -- IN
        sp_control          => sp_control,          -- IN
        sample_nbt          => sample_nbt,          -- IN
        sample_dbt          => sample_dbt,          -- IN
        sample_sec          => sample_sec_i,        -- IN
        data_tx             => data_tx,             -- IN
        data_tx_delayed     => data_tx_delayed,     -- IN
        data_rx_nbt         => data_rx_nbt,         -- IN
        can_rx_i            => can_rx_i,            -- IN
        
        bit_error           => bit_Error            -- OUT
    );

    ----------------------------------------------------------------------------
    -- Sampling of bus value
    ----------------------------------------------------------------------------
    sample_mux_inst : sample_mux
    generic map(
        G_RESET_POLARITY       => G_RESET_POLARITY
    )
    port map(
        clk_sys                => clk_sys,          -- IN
        res_n                  => res_n,            -- IN
        drv_ena                => drv_ena,          -- IN
        sp_control             => sp_control,       -- IN
        sample_nbt             => sample_nbt,       -- IN
        sample_dbt             => sample_dbt,       -- IN
        sample_sec             => sample_sec_i,     -- IN
        data_rx_nbt            => data_rx_nbt,      -- IN
        can_rx_i               => can_rx_i,         -- IN
        
        prev_sample            => prev_sample,      -- OUT
        data_rx                => data_rx           -- OUT
    );

    -- Output data propagation - Pipe directly - no delay
    CAN_tx             <= data_tx;

    -- As synchroniation edge, valid edge on RX Data is selected!
    sync_edge          <= edge_rx_valid;

    -- Registers to output propagation
    sample_sec         <=  sample_sec_i;

end architecture;