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
-- @TestInfoStart
--
-- @Purpose:
--  TX Priority feature test.
--
-- @Verifies:
--  @1. If during TX frame validation by TX Arbitrator CAN Core issues lock
--      command (another frame has been validated before), then first frame will
--      be transmitted (in other words, TX arbitration mechanism will not
--      corrupt consistency of data/metadata of CAN frame).
--
-- @Test sequence:
--  @1. Generate two random frames and insert them to TXT Buffer 1 and 2.
--      Configure priority of TXT Buffer 1 higher than TXT Buffer 2.
--  @2. Wait until sample point and issue Set ready command to TXT Buffer 2.
--  @3. Wait for nearly whole Bit time, and before next sample point, issue
--      Set ready command to TXT Buffer 1. This will re-invoke TXT Buffer
--      validation process with TXT Buffer 1. Time the command, so that when
--      Lock command is issued by CAN Core, TX Arbitrator FSM is always in
--      different state of TX frame validation.
--  @4. Wait until frame is sent, and verify that either frame 2 or frame 1 were
--      sent (it depends on when did the validation finish, which depends on
--      delay between frames!). This verifies that no part of metadata has
--      been taken from other frame, and frame was validated atomically!
--      
--
-- @TestInfoEnd
--------------------------------------------------------------------------------
-- Revision History:
--      29.11.2020   Created file
--------------------------------------------------------------------------------

Library ctu_can_fd_tb;
context ctu_can_fd_tb.ctu_can_synth_context;
context ctu_can_fd_tb.ctu_can_test_context;

use ctu_can_fd_tb.pkg_feature_exec_dispath.all;

package tx_arb_consistency_feature is

    procedure tx_arb_consistency_feature_exec(
        signal      so              : out    feature_signal_outputs_t;
        signal      rand_ctr        : inout  natural range 0 to RAND_POOL_SIZE;
        signal      iout            : in     instance_outputs_arr_t;
        signal      mem_bus         : inout  mem_bus_arr_t;
        signal      bus_level       : in     std_logic
    );
end package;


package body tx_arb_consistency_feature is

    procedure tx_arb_consistency_feature_exec(
        signal      so              : out    feature_signal_outputs_t;
        signal      rand_ctr        : inout  natural range 0 to RAND_POOL_SIZE;
        signal      iout            : in     instance_outputs_arr_t;
        signal      mem_bus         : inout  mem_bus_arr_t;
        signal      bus_level       : in     std_logic
    ) is
        variable ID_1               :       natural := 1;   -- Transmiter
        variable ID_2               :       natural := 2;   -- Receiver          

        variable CAN_frame_rx_1     :       SW_CAN_frame_type;
        variable CAN_frame_rx_2     :       SW_CAN_frame_type;
        variable CAN_frame_tx_1     :       SW_CAN_frame_type;
        variable CAN_frame_tx_2     :       SW_CAN_frame_type;
        
        variable frame_equal        :       boolean := false;
        variable tmp_int            :       natural := 0;
        
        variable wait_cycles        :       natural := 0;
        variable bus_timing         :       bit_time_config_type;
        
        variable frames_equal_1     :       boolean;
        variable frames_equal_2     :       boolean;
    begin

        -----------------------------------------------------------------------
        -- @1. Generate two random frames and insert them to TXT Buffer 1 and
        --     2. Configure priority of TXT Buffer 1 higher than TXT Buffer 2.
        -----------------------------------------------------------------------
        info("Step 1");

        CAN_generate_frame(rand_ctr, CAN_frame_tx_1);
        CAN_generate_frame(rand_ctr, CAN_frame_tx_2);
        
        CAN_insert_TX_frame(CAN_frame_tx_1, 1, ID_1, mem_bus(1));
        CAN_insert_TX_frame(CAN_frame_tx_2, 2, ID_1, mem_bus(1));
        
        CAN_configure_tx_priority(1, 5, ID_1, mem_bus(1)); 
        CAN_configure_tx_priority(2, 3, ID_1, mem_bus(1));
        
        CAN_read_timing_v(bus_timing, ID_1, mem_bus(1));

        -----------------------------------------------------------------------
        -- @2. Wait until sample point and issue Set ready command to TXT
        --     Buffer 2.
        -----------------------------------------------------------------------
        info("Step 2");

        CAN_wait_sample_point(iout(1).stat_bus, false);
        send_TXT_buf_cmd(buf_set_ready, 2, ID_1, mem_bus(1));

        -----------------------------------------------------------------------
        -- @3. Wait for nearly whole Bit time, and before next sample point,
        --     issue Set ready command to TXT Buffer 1. This will re-invoke TXT
        --     Buffer validation process with TXT Buffer 1. Time the command, so
        --     that when Lock command is issued by CAN Core, TX Arbitrator FSM
        --     is always in different state of TX frame validation.
        -----------------------------------------------------------------------
        info("Step 3");

        CAN_wait_sync_seg(iout(1).stat_bus);
        
        rand_int_v(rand_ctr, 10, wait_cycles);
        wait_cycles := wait_cycles - 1 + bus_timing.tq_nbt *
                        (bus_timing.prop_nbt + bus_timing.ph1_nbt);

        for i in 0 to wait_cycles loop
            wait until rising_edge(mem_bus(1).clk_sys);
        end loop;
        
        send_TXT_buf_cmd(buf_set_ready, 1, ID_1, mem_bus(1));

        -----------------------------------------------------------------------
        -- @4. Wait until frame is sent, and verify that either frame 2 or
        --     frame 1 were sent (it depends on when did the validation finish,
        --     which depends on delay between frames!). This verifies that no
        --     part of metadata has been taken from other frame, and frame was
        --     validated atomically!
        -----------------------------------------------------------------------
        CAN_wait_frame_sent(ID_2, mem_bus(2));
        
        CAN_read_frame(CAN_frame_rx_1, ID_2, mem_bus(2));
        CAN_compare_frames(CAN_frame_rx_1, CAN_frame_tx_1, false, frames_equal_1);
        CAN_compare_frames(CAN_frame_rx_1, CAN_frame_tx_2, false, frames_equal_2);
        
        check(frames_equal_1 or frames_equal_2,
                "First frame was properly received!");
                
        CAN_wait_frame_sent(ID_2, mem_bus(2));
        CAN_read_frame(CAN_frame_rx_2, ID_2, mem_bus(2));
        if (frames_equal_1) then
            CAN_compare_frames(CAN_frame_rx_2, CAN_frame_tx_2, false, frames_equal_1);
        elsif (frames_equal_2) then
            CAN_compare_frames(CAN_frame_rx_2, CAN_frame_tx_1, false, frames_equal_1);
        end if;

        check(frames_equal_1, "Second frame was properly received!");

        CAN_wait_bus_idle(ID_1, mem_bus(1));
        CAN_wait_bus_idle(ID_2, mem_bus(2));

    end procedure;
end package body;
