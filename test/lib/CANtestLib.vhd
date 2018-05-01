--------------------------------------------------------------------------------
-- 
-- CTU CAN FD IP Core
-- Copyright (C) 2015-2018 Ondrej Ille <ondrej.ille@gmail.com>
-- 
-- Project advisors and co-authors: 
-- 	Jiri Novak <jnovak@fel.cvut.cz>
-- 	Pavel Pisa <pisa@cmp.felk.cvut.cz>
-- 	Martin Jerabek <jerabma7@fel.cvut.cz>
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
--  Purpose:
--    Main test library for CTU CAN FD controller. Contains all test resources 
--    for running CANTest framework and low-level access functions.
--
--    Note that in this library several types are (nearly) the same as types
--    in synthesizable code! This is done on purpose, to avoid using wrongly
--    defined values. These types are defined from documentation manually.
--
--------------------------------------------------------------------------------
-- Revision History:
--    27.5.2016   Created file
--    13.1.2017   Added formatting of identifier in CAN_send_frame, 
--                CAN_read_frame to fit the native decimal interpretation 
--                (the same way as in C driver)
--    27.11.2017  Added "reset_test" function fix. Implemented reset synchroniser
--                to avoid async reset in the core. As consequnce after the core
--                reset is released, the core has to wait at least TWO clock
--                cycles till the reset is synchronised and deasserted.
--    06.02.2018  Modified the library to work with generated constants from the
--                8 bit register map generated from IP-XACT.
--    09.02.2018  Added support fow RWCNT field in the SW_CAN_Frame.
--    15.02.2018  Added support for TXT Buffer commands in CAN Send frame 
--                procedure.
--    23.02.2018  Corrected "CAN_generate_frame" function for proper placement
--                of BASE identifier to unsigned value.
--     28.4.2018  Converted TXT Buffer access functions to use generated macros.
--      1.5.2018  1. Added HAL layer types and functions.
--                2. Added Byte enable support to memory access functions.
--------------------------------------------------------------------------------

Library ieee;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.ALL;
use STD.textio.all;
use IEEE.std_logic_textio.all;
USE ieee.math_real.ALL;
USE work.randomLib.All;
use work.CANconstants.all;

use work.CAN_FD_register_map.all;
use work.CAN_FD_frame_format.all;

package CANtestLib is

    ----------------------------------------------------------------------------
    ----------------------------------------------------------------------------
    -- Types
    ----------------------------------------------------------------------------
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    --Common test types
    ----------------------------------------------------------------------------

    -- Logger severity type (severities in increasing order)
    type log_lvl_type is (
        info_l,
        warning_l,
        error_l
    );

    -- Behaviour of the test when error occurs
    type err_beh_type is (
        quit,
        go_on
    );

    -- Status of test
    type test_status_type is (
        waiting,
        running,
        passed,
        failed
    );


    ----------------------------------------------------------------------------
    -- Memory access types
    ----------------------------------------------------------------------------

    -- Avalon bus access size (to support "byte enable" functionality)
    type aval_access_size is (
        BIT_8,
        BIT_16,
        BIT_32
    );

    ----------------------------------------------------------------------------
    -- Core common types for register map (generated in future)
    -- Implemented to create HAL like abstraction and allow easier modifications
    -- of register map without touching the test code!
    ----------------------------------------------------------------------------
   
    -- Controller modes
    type SW_mode is record
        reset                   :   boolean;
        listen_only             :   boolean;
        self_test               :   boolean;
        acceptance_filter       :   boolean;
        flexible_data_rate      :   boolean;
        rtr_pref                :   boolean;
        tripple_sampling        :   boolean;
        acknowledge_forbidden   :   boolean;
    end record;


    -- Controller commands
    type SW_command is record
        abort_transmission      :   boolean;
        release_rec_buffer      :   boolean;
        clear_data_overrun      :   boolean;
    end record;


    -- Controller status
    type SW_status is record
        receive_buffer          :   boolean;
        data_overrun            :   boolean;
        transceive_buffer       :   boolean;
        error_transmission      :   boolean;
        receiver                :   boolean;
        transmitter             :   boolean;
        error_warning           :   boolean;
        bus_status              :   boolean;
    end record;


    -- Controller settings
    type SW_settings is record
        retransmitt_limit_ena   :   boolean;
        retransmitt_th          :   natural range 0 to 15;
        internal_loopback       :   boolean;
        enable                  :   boolean;
        fd_type                 :   boolean;
    end record;


    -- Transmitt buffer HW command
    type SW_interrupts is record
        receive_int             :   boolean;
        transmitt_int           :   boolean;
        error_warning_int       :   boolean;
        data_overrun_int        :   boolean;
        error_passive_int       :   boolean;
        arb_lost_int            :   boolean;
        bus_error_int           :   boolean;
        logger_finished_int     :   boolean;
        rx_buffer_full_int      :   boolean;
        bit_rate_shift_int      :   boolean;
        rx_buffer_not_empty_int :   boolean;
        tx_buffer_hw_cmd        :   boolean;
    end record;


    -- Error limits (Normal and special)
    type SW_err_counters is record
        error_warning_limit     :   natural range 0 to 255;
        error_passive_limit     :   natural range 0 to 255;
    end record;
    

    -- Fault confinement states
    type SW_fault_state is (
        fc_error_active,
        fc_error_passive,
        fc_bus_off
    );


    -- Error counters (Normal and special)
    type SW_error_counters is record
        rx_counter              :   natural range 0 to 2 ** 16 - 1;
        tx_counter              :   natural range 0 to 2 ** 16 - 1;
        err_norm                :   natural range 0 to 2 ** 16 - 1;
        err_fd                  :   natural range 0 to 2 ** 16 - 1;
    end record;


    -- RX Buffer info and status
    type SW_RX_Buffer_info is record
        rx_buff_size            :   natural range 0 to 2 ** 13 - 1;
        rx_mem_free             :   natural range 0 to 2 ** 13 - 1;
        rx_write_pointer        :   natural range 0 to 2 ** 13 - 1;
        rx_read_pointer         :   natural range 0 to 2 ** 13 - 1;
        rx_full                 :   boolean;
        rx_empty                :   boolean;
        rx_frame_count          :   natural range 0 to 2 ** 11 - 1;
    end record;


    -- RX Buffer options
    type SW_RX_Buffer_options is record
        rx_time_stamp_options   :   boolean;
    end record;


    -- TXT Buffer priorities
    type SW_TXT_priority is record
        txt_buffer_1_priority   :   natural range 0 to 7;
        txt_buffer_2_priority   :   natural range 0 to 7;
        txt_buffer_3_priority   :   natural range 0 to 7;
        txt_buffer_4_priority   :   natural range 0 to 7;
    end record;




    ----------------------------------------------------------------------------
    -- Message filter types
    ----------------------------------------------------------------------------

    -- Frame information on input of message filter    
    type mess_filter_input_type is record
        rec_ident_in            :   std_logic_vector(28 downto 0);
        ident_type              :   std_logic;
        frame_type              :   std_logic;
        rec_ident_valid         :   std_logic; 
    end record;

    -- Driving bus values on the input off message filter
    type mess_filter_drv_type is record

        -- Filter A bit mask, control bits and bit value
        drv_filter_A_mask       :   std_logic_vector(28 downto 0);
        drv_filter_A_ctrl       :   std_logic_vector(3 downto 0);
        drv_filter_A_bits       :   std_logic_vector(28 downto 0);
      
        -- Filter B bit mask, control bits and bit value
        drv_filter_B_mask       :   std_logic_vector(28 downto 0);
        drv_filter_B_ctrl       :   std_logic_vector(3 downto 0);
        drv_filter_B_bits       :   std_logic_vector(28 downto 0);
      
        -- Filter C bit mask, control bits and bit value
        drv_filter_C_mask       :   std_logic_vector(28 downto 0);
        drv_filter_C_ctrl       :   std_logic_vector(3 downto 0);
        drv_filter_C_bits       :   std_logic_vector(28 downto 0);
       
        -- Range filter control bits, lower and upper thresholds
        drv_filter_ran_ctrl     :   std_logic_vector(3 downto 0);
        drv_filter_ran_lo_th    :   std_logic_vector(28 downto 0);
        drv_filter_ran_hi_th    :   std_logic_vector(28 downto 0);

        -- Filters are enabled
        drv_filters_ena         :   std_logic;

    end record;

    ----------------------------------------------------------------------------
    -- Prescaler types
    ----------------------------------------------------------------------------
    
    -- Driving bus settings for prescaler
    type presc_drv_type is record
         
        -- Time quanta (Nominal and Data)
        drv_tq_nbt              :   std_logic_vector (7 downto 0);
        drv_tq_dbt              :   std_logic_vector (7 downto 0);

        -- Propagation segment (Nominal and Data)
        drv_prs_nbt             :   std_logic_vector (6 downto 0);
        drv_prs_dbt             :   std_logic_vector (5 downto 0);

        -- Phase 1 segment (Nominal and Data)
        drv_ph1_nbt             :   std_logic_vector (5 downto 0);
        drv_ph1_dbt             :   std_logic_vector (4 downto 0);

        -- Phase 2 segment (Nominal and Data)
        drv_ph2_nbt             :   std_logic_vector (5 downto 0); 
        drv_ph2_dbt             :   std_logic_vector (4 downto 0); 

        -- Synchronisation jump width (Nominal and Data)
        drv_sjw_nbt             :   std_logic_vector(4 downto 0);
        drv_sjw_dbt             :   std_logic_vector(4 downto 0);

    end record;

    -- Triggering signals joined to single record
    type presc_triggers_type is record
       
        -- Sample signal (Nominal and Data)
        -- (Used for bus sampling)
        sample_nbt              :   std_logic;
        sample_dbt              :   std_logic;

        -- Sample signal delayed by one clock cycle (Nominal and Data)
        -- (Used for Bit destuffing)
        sample_nbt_del_1        :   std_logic;
        sample_dbt_del_1        :   std_logic;

        -- Sample signal delayed by two clock cycle (Nominal and Data)
        -- (Used for Processing the data by Protocol control)
        sample_nbt_del_2        :   std_logic;
        sample_dbt_del_2        :   std_logic;

        -- Synchronisation signal
        -- (Used to transmitt data)
        sync_nbt                :   std_logic;
        sync_dbt                :   std_logic;

        -- Synchronisation signal by one clock cycle (Nominal and Data)
        -- (Used for Bit stuffing)
        sync_nbt_del_1          :   std_logic;
        sync_dbt_del_1          :   std_logic;
    end record;


    ----------------------------------------------------------------------------
    -- RX Buffer types
    ----------------------------------------------------------------------------
    type CAN_frame_type is record

        -- Message Identifier
        rec_ident_in            :   std_logic_vector(28 downto 0);

        -- Message Data (up to 64 bytes);
        rec_data_in             :   std_logic_vector(511 downto 0);

        -- Data length code
        rec_dlc_in              :   std_logic_vector(3 downto 0);

        -- Recieved identifier type (0-BASE Format, 1-Extended Format);
        rec_ident_type_in       :   std_logic;

        -- Recieved frame type (0-Normal CAN, 1- CAN FD)
        rec_frame_type_in       :   std_logic;

        -- Recieved frame is RTR Frame(0-No, 1-Yes)
        rec_is_rtr              :   std_logic;

        -- Whenever frame was recieved with BIT Rate shift 
        rec_brs                 :   std_logic;

        -- Error state indicator
        rec_esi                 :   std_logic;

        -- Output from acceptance filters (out_ident_valid) if message 
        -- fits the filters
        rec_message_valid       :   std_logic;

        --Number of words frame takes in the RX Buffer without FRAME_FORMAT word 
        rec_rwcnt               :   std_logic_vector(4 downto 0);

    end record;


    ----------------------------------------------------------------------------
    -- TXT Buffer types
    ----------------------------------------------------------------------------
    
    -- TXT Buffer state (used in test access, not in synthesizable code)
    type SW_TXT_Buffer_state_type is (
        buf_empty,
        buf_ready,
        buf_tx_progress,
        buf_ab_progress,
        buf_aborted,
        buf_failed,
        buf_done
    );

    -- TXT Buffer commands (used in test access, not synthesizable code)
    type SW_TXT_Buffer_command_type is (
        buf_set_empty,
        buf_set_ready,
        buf_set_abort
    );



    ----------------------------------------------------------------------------
    -- Avalon memory interface type
    ----------------------------------------------------------------------------
    type Avalon_mem_type is record
        clk_sys                 :   std_logic;
        data_in                 :   std_logic_vector(31 downto 0);
        data_out                :   std_logic_vector(31 downto 0);
        address                 :   std_logic_vector(23 downto 0);
        scs                     :   std_logic;
        swr                     :   std_logic;
        srd                     :   std_logic;
        sbe                     :   std_logic_vector(3 downto 0);
    end record;


    ----------------------------------------------------------------------------
    -- Main Bus timing configuration type used in feature and sanity tests
    -- (using "naturals" instead of std_logic_vector)
    ----------------------------------------------------------------------------
    type bit_time_config_type is record
         tq_nbt                 :   natural;
         tq_dbt                 :   natural;
         prop_nbt               :   natural;
         ph1_nbt                :   natural;
         ph2_nbt                :   natural;
         sjw_nbt                :   natural;
         prop_dbt               :   natural;
         ph1_dbt                :   natural;
         ph2_dbt                :   natural;
         sjw_dbt                :   natural;
    end record;


    ----------------------------------------------------------------------------
    -- Software CAN Frame type. Used for generation, transmission, reception,
    -- comparison of CAN Frames.
    ----------------------------------------------------------------------------
    type SW_CAN_frame_type is record

        -- CAN Identifier. Decimal value. Note that the value differs for
        -- BASE and EXTENDED Identifiers!
        identifier              :   natural;

        -- Data payload
        data                    :   std_logic_vector(511 downto 0);

        -- Data length code as defined in CAN Standard
        dlc                     :   std_logic_vector(3 downto 0);

        -- Data length in bytes
        data_length             :   natural range 0 to 64;

        -- Identifier type (0 - BASE Format, 1 - Extended Format);
        ident_type              :   std_logic;

        -- Frame type (0 - Normal CAN, 1 - CAN FD)
        frame_format            :   std_logic;

        -- RTR Flag (0 - No RTR Frame, 1 - RTR Frame)
        rtr                     :   std_logic;

        -- Bit rate shift flag
        brs                     :   std_logic;

        -- Timestamp (as defined in TIMESTAMP_U_W and TIMESTAMP_L_W)
        timestamp               :   std_logic_vector(63 downto 0);

        -- Receive word count field as stored in RX Buffer FRAME_FORM_W.
        -- Indicates number of 32 bit words which Frame ocupies in RX Buffer
        -- without FRAME_FORM_W.
        -- Note that this value is valid only for received frames and has
        -- no meaning in TXT Buffer.
        rwcnt                   :   natural;

    end record;

    ----------------------------------------------------------------------------
    -- Transceiver delay type
    ----------------------------------------------------------------------------
    type tran_delay_type is record
        tx_delay_sr             :   std_logic_vector(255 downto 0);
        rx_delay_sr             :   std_logic_vector(255 downto 0);
        tx_point                :   std_logic;
        rx_point                :   std_logic;
    end record;



    ----------------------------------------------------------------------------
    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------
    ----------------------------------------------------------------------------
    constant f100_MHZ           :   natural := 10000;



    ----------------------------------------------------------------------------
    ----------------------------------------------------------------------------
    -- Functions definitions
    ----------------------------------------------------------------------------
    ----------------------------------------------------------------------------

  
    ----------------------------------------------------------------------------
    -- Function called at the end of the test which evaluates results of test.
    -- If Error threshold is bigger than number of errors which ocurred in the
    -- test, test status will be updated to "passed", if not, test status will
    -- be updated to "failed". After the evaluation test simulation is finished.
    --
    -- Arguments:
    --  error_th        Error threshold.
    --  errors          Number of errors which occurred in the test
    --  status          Status to be updated 
    ----------------------------------------------------------------------------
    procedure evaluate_test(
        signal error_th         : in    natural;
        signal errors           : in    natural;
        signal status           : out   test_status_type
    );


    ----------------------------------------------------------------------------
    -- Generates clock signal for the test with custom period, duty cycle and
    -- clock jitter.
    --
    -- Arguments:
    --  period          Period of generated clock in picoseconds.
    --  duty            Duty cycle of generated clock in percents.
    --  epsilon_ppm     Clock uncertainty (jitter) which is always added to the
    --                  default clock period.
    --  out_clk         Generated clock.
    ----------------------------------------------------------------------------
    procedure generate_clock(
        constant period         : in    natural;
        constant duty           : in    natural;
        constant epsilon_ppm    : in    natural;
        signal   out_clk        : out   std_logic
    );


    ----------------------------------------------------------------------------
    -- Reports message when severity level is lower or equal than severity
    -- of message.
    --
    -- Arguments:
    --  message         String to be reported.
    --  log_severity    Severity level which is set in current test.
    --  log_level       Severity of message
    ----------------------------------------------------------------------------
    procedure log(
        constant message        : in    String;
        constant log_severity   : in    log_lvl_type;
        signal   log_level      : in    log_lvl_type
    );


    ----------------------------------------------------------------------------
    -- Asserts reset signal to restart the operated circuit. Then waits until
    -- run condition signal becomes "true" and sets test status to "running" and
    -- sets error counter to 0. Finally, deasserts reset signal.
    --
    -- Arguments:
    --  res_n           Reset signal (active low).
    --  status          Test status to assert "running".
    --  run             Run condition to wait until comes true.
    --  error_ctr       Error counter to erase.
    ----------------------------------------------------------------------------
    procedure reset_test(
        signal res_n            : out   std_logic;
        signal status           : out   test_status_type;
        signal run              : in    boolean;
        signal error_ctr        : out   natural
    );


    ----------------------------------------------------------------------------
    -- Process error ocurrence in the test. This consists of following steps:
    --  1. Increment error counter
    --  2. If Error behaviour is "quit", assert Immediate exit flag to "true".
    --     Otherwise assert Immediate exit flag to "false".
    -- 
    -- Arguments:
    --  error_ctr       Error counter to increment.
    --  error_beh       Error behaviour to evaluate.
    --  exit_imm        Immediate exit flag to assert.
    ----------------------------------------------------------------------------
    procedure process_error(
        signal error_ctr        : inout natural;
        signal error_beh        : in    err_beh_type;
        signal exit_imm         : out   boolean
    );


    ----------------------------------------------------------------------------
    -- Print basic testbench information.
    -- 
    -- Arguments:
    --  iterations      Number of iterations to execute in test.
    --  log_level       Severity level which is set in actual frame.
    --  error_beh       Error behaviour of test.
    --  error_tol       Error tolerance of test.
    ----------------------------------------------------------------------------
    procedure print_test_info(
        signal iterations       : in    natural;
        signal log_level        : in    log_lvl_type;
        signal error_beh        : in    err_beh_type;
        signal error_tol        : in    natural
    );


    ----------------------------------------------------------------------------
    -- Decode data length code from value as defined in CAN FD Standard to
    -- length of frame in bytes.
    -- 
    -- Arguments:
    --  dlc             Data length code as received or transmitted.
    --  length          Length of CAN Frame in bytes       
    ----------------------------------------------------------------------------
    procedure decode_dlc(
        signal   dlc            : in    std_logic_vector(3 downto 0);
        variable length         : out   natural
    );


    ----------------------------------------------------------------------------
    -- Decode data length code from value as defined in CAN FD Standard to
    -- length of frame in bytes. (Variable output)
    -- 
    -- Arguments:
    --  dlc             Data length code as received or transmitted.
    --  length          Length of CAN Frame in bytes       
    ----------------------------------------------------------------------------
    procedure decode_dlc_v(
        constant dlc            : in    std_logic_vector(3 downto 0);
        variable length         : out   natural
    );


    ----------------------------------------------------------------------------
    -- Decode Read word count value as present in FRAME_FORMAT_W of RX Buffer
    -- from DLC. Read word count value indicates how many 32-bit words will the
    -- buffer occupy in RX Buffer without Frame Format word.
    -- 
    -- Arguments:
    --  dlc             Data length code to decode as transmitted or received.
    --  rwcnt           Read word count value.
    ----------------------------------------------------------------------------
    procedure decode_dlc_rx_buff(
        constant dlc            : in    std_logic_vector(3 downto 0);
        variable rwcnt          : out   natural
    );


    ----------------------------------------------------------------------------
    -- Decode number of 32-bit words CAN Frame will occupy in RX Buffer
    -- (together with Frame format word).
    -- 
    -- Arguments:
    --  dlc             Data length code to decode as transmitted or received.
    --  buff_space      Number of 32-bit words.
    ----------------------------------------------------------------------------
    procedure decode_dlc_buff(
        signal   dlc            : in    std_logic_vector(3 downto 0);
        variable buff_space     : out   natural
    );
    

    ----------------------------------------------------------------------------
    -- Generate simple triggering signals.
    -- Two signals are generated, "sync" and "sample". No bit rate switch is
    -- implemented in this procedure. There is random amount of clock cycles 
    -- between sync and sample, but not less than "min_diff" and not more than 
    -- 10 clock cycles! "min_diff" is intended for determining how many clock 
    -- cycles each circuit needs between bit transmittion and reception!
    -- 
    -- Arguments:
    --  rand_ctr        Pointer to random pool.
    --  sync            Synchronisation trigger (for transmission)
    --  sample          Sampling trigger (for reception)
    --  clk_sys         Clock signal
    --  min_diff        Minimal gap (in clock cycles) between sync and sample
    --                  signals.
    ----------------------------------------------------------------------------
    procedure generate_simple_trig(
        signal   rand_ctr       : inout natural range 0 to RAND_POOL_SIZE;
        signal   sync           : out   std_logic;
        signal   sample         : out   std_logic;
        signal   clk_sys        : in    std_logic;
        variable min_diff       : in    natural
    );


    procedure generate_trig(
        signal    sync          : out   std_logic;
        signal    sample        : out   std_logic;
        signal    clk_sys       : in    std_logic;
        signal    seg1          : in    natural;
        signal    seg2          : in    natural
    );
  

    ----------------------------------------------------------------------------
    -- Memory access routines
    ----------------------------------------------------------------------------

    ----------------------------------------------------------------------------
    -- Execute write access on Avalon memory bus. Does not support unaligned
    -- accesses.
    -- 
    -- Arguments:
    --  w_data          Data to write.
    --  w_address       Address where to write the data
    --  w_size          Size of the access (8 Bit, 16 bit or 32 bit)
    --  mem_bus         Avalon memory bus to execute the access on.
    ----------------------------------------------------------------------------
    procedure aval_write(
        constant  w_data        : in    std_logic_vector(31 downto 0);
        constant  w_address     : in    std_logic_vector(23 downto 0);
        constant  w_size        : in    aval_access_size;
        signal    mem_bus       : inout Avalon_mem_type
    );


    ----------------------------------------------------------------------------
    -- Execute read access on Avalon memory bus. Does not supports unaligned
    -- accesses.
    -- 
    -- Arguments:
    --  r_data          Variable in which Read data will be returned.
    --  r_address       Address to read the data from.
    --  r_size          Size of the access (8 Bit, 16 bit or 32 bit)
    --  mem_bus         Avalon memory bus to execute the access on.
    ----------------------------------------------------------------------------
    procedure aval_read(
        variable  r_data        : out   std_logic_vector(31 downto 0);
        constant  r_address     : in    std_logic_vector(23 downto 0);
        constant  r_size        : in    aval_access_size;
        signal    mem_bus       : inout Avalon_mem_type
    );


    ----------------------------------------------------------------------------
    -- Execute write access to CTU CAN FD Core over Avalon Bus. If size is not
    -- specified, 32 bit access is executed.
    --
    -- Address bits meaning is following:
    --  [19:16]     Component type (always CAN_COMPONENT_TYPE)
    --  [15:12]     Identifier (Index) of core. Allows to distinguish between
    --              up to 16 instances of CTU CAN FD Core.
    --  [11:0]      Register or Buffer offset within a the core.
    -- 
    -- Arguments:
    --  w_data          Data to write to CTU CAN FD Core.
    --  w_offset        Register or buffer offset (bits 11:0).
    --  ID              Index of CTU CAN FD Core instance (bits 15:12)
    --  mem_bus         Avalon memory bus to execute the access on.
    ----------------------------------------------------------------------------
    procedure CAN_write(
        constant  w_data        : in    std_logic_vector(31 downto 0);
        constant  w_offset      : in    std_logic_vector(11 downto 0);
        constant  ID            : in    natural range 0 to 15;
        signal    mem_bus       : inout Avalon_mem_type;
        constant  w_size        : in    aval_access_size := BIT_32
    );


    ----------------------------------------------------------------------------
    -- Execute read access from CTU CAN FD Core over Avalon Bus. If size is not
    -- specified, 32 bit access is executed.
    --
    -- Address bits meaning is following:
    --  [19:16]     Component type (always CAN_COMPONENT_TYPE)
    --  [15:12]     Identifier (Index) of core. Allows to distinguish between
    --              up to 16 instances of CTU CAN FD Core.
    --  [11:0]      Register or Buffer offset within a the core.
    -- 
    -- Arguments:
    --  r_data          Variable in which Read data will be returned.
    --  r_offset        Register or buffer offset (bits 11:0).
    --  ID              Index of CTU CAN FD Core instance (bits 15:12)
    --  mem_bus         Avalon memory bus to execute the access on.
    ----------------------------------------------------------------------------
    procedure CAN_read(
        variable  r_data        : out   std_logic_vector(31 downto 0);
        constant  r_offset      : in    std_logic_vector(11 downto 0);
        constant  ID            : in    natural range 0 to 15;
        signal    mem_bus       : inout Avalon_mem_type;
        constant  r_size        : in    aval_access_size := BIT_32
    ); 




    ----------------------------------------------------------------------------
    -- CAN configuration routines
    ----------------------------------------------------------------------------
    
    ----------------------------------------------------------------------------
    -- Configure Bus timing on CTU CAN FD Core.
    -- (duration of bit phases, synchronisation jump width, baud-rate prescaler)
    -- 
    -- Arguments:
    --  bus_timing      Bus timing structure that contains timing configuration
    --  ID              Index of CTU CAN FD Core instance
    --  mem_bus         Avalon memory bus to execute the access on.
    ----------------------------------------------------------------------------
    procedure CAN_configure_timing(
        constant bus_timing     : in    bit_time_config_type;
        constant ID             : in    natural range 0 to 15;
        signal   mem_bus        : inout Avalon_mem_type    
    );


    ----------------------------------------------------------------------------
    -- Read Bus timing configuration from CTU CAN FD Core.
    -- (duration of bit phases, synchronisation jump width, baud-rate prescaler)
    -- 
    -- Arguments:
    --  bus_timing      Bus timing structure that will be filled by timing
    --                  configuration.
    --  ID              Index of CTU CAN FD Core instance
    --  mem_bus         Avalon memory bus to execute the access on.
    ----------------------------------------------------------------------------
    procedure CAN_read_timing(
        signal   bus_timing     : out   bit_time_config_type;
        constant ID             : in    natural range 0 to 15;
        signal   mem_bus        : inout Avalon_mem_type  
    );


    ----------------------------------------------------------------------------
    -- Turn on/off CTU_CAN_FD Core.
    -- 
    -- Arguments:
    --  turn_on         Turns on the Core when "true". Turns off otherwise.
    --  ID              Index of CTU CAN FD Core instance
    --  mem_bus         Avalon memory bus to execute the access on.
    ----------------------------------------------------------------------------
    procedure CAN_turn_controller(
        constant turn_on        : in    boolean;
        constant ID             : in    natural range 0 to 15;
        signal   mem_bus        : inout Avalon_mem_type    
    );


    ----------------------------------------------------------------------------
    -- Enables/Disabled Retransmitt limiting in CTU CAN FD Core.
    -- 
    -- Arguments:
    --  enable          Enables retransmitt limiting when "true".
    --                  Disables rettransmitt limiting otherwise.
    --  limit           Limit for number of retransmissions.
    --  ID              Index of CTU CAN FD Core instance
    --  mem_bus         Avalon memory bus to execute the access on.
    ----------------------------------------------------------------------------
    procedure CAN_enable_retr_limit(
        constant enable         : in    boolean;
        constant limit          : in    natural range 0 to 15;
        constant ID             : in    natural range 0 to 15;
        signal   mem_bus        : inout Avalon_mem_type    
    );


    ----------------------------------------------------------------------------
    -- Generate random CAN FD Frame.
    -- 
    -- Arguments:
    --  rand_ctr        Pointer to pool of random values.
    --  frame           Output variable in which CAN FD Frame sill be generated.
    ---------------------------------------------------------------------------- 
    procedure CAN_generate_frame(
        signal   rand_ctr       : inout natural range 0 to RAND_POOL_SIZE;
        variable frame          : inout SW_CAN_frame_type
    );


    ----------------------------------------------------------------------------
    -- Compare two CAN FD frames and decide if they are equal.
    -- 
    -- Arguments:
    --  frame_A         First frame in comparison
    --  frame_B         Second frame in comparison
    --  comp_ts         When "true" timestamps should be considered in
    --                  comparison. When "false" timestamps should not be
    --                  considered.
    --  outcome         Variable to store result of comparison into. When frames
    --                  are equal "true" is stored, "false" otherwise.
    ----------------------------------------------------------------------------   
    procedure CAN_compare_frames(
        constant frame_A        : in    SW_CAN_frame_type;
        constant frame_B        : in    SW_CAN_frame_type;
        constant comp_ts        : in    boolean;
        variable outcome        : inout boolean
    );


    ----------------------------------------------------------------------------
    -- Check whether TXT Buffer is accessible (Empty, Aborted, TX Failed or Done)
    -- If yes, insert the frame to TXT Buffer and give "set_ready" command.
    -- The function does not wait until the frame is transmitted.
    -- 
    -- Arguments:
    --  frame           CAN FD Frame to send
    --  buf_nr          Number of TXT Buffer from which the frame should be
    --                  sent (1:4)
    --  ID              Index of CTU CAN FD Core instance
    --  mem_bus         Avalon memory bus to execute the access on.
    --  outcome         Returns "true" if the frame was inserted properly, 
    --                  "false" if TXT Buffer was in states : Ready,
    --                  TX in progress, Abort in progress
    ---------------------------------------------------------------------------- 
    procedure CAN_send_frame(
        constant frame          : in    SW_CAN_frame_type;
        constant buf_nr         : in    natural range 1 to 4;
        constant ID             : in    natural range 0 to 15;
        signal   mem_bus        : inout Avalon_mem_type;
        variable outcome        : out   boolean
    );


    ----------------------------------------------------------------------------
    -- Reads CAN Frame from RX Buffer FIFO.
    -- 
    -- Arguments:
    --  frame           Output variable where CAN FD Frame will be stored
    --  ID              Index of CTU CAN FD Core instance
    --  mem_bus         Avalon memory bus to execute the access on.
    ----------------------------------------------------------------------------
    procedure CAN_read_frame(
        variable frame          : inout SW_CAN_frame_type;
        constant ID             : in    natural range 0 to 15;
        signal   mem_bus        : inout Avalon_mem_type
    );


    ----------------------------------------------------------------------------
    -- Waits until frame starts (unit turns transceiver or receiver),
    -- and then waits until frame finishes (bus becomes idle).
    --
    -- Procedure is polling on status of CTU CAN FD Core over Avalon bus!
    -- 
    -- Arguments:
    --  ID              Index of CTU CAN FD Core instance
    --  mem_bus         Avalon memory bus to execute the access on.
    ----------------------------------------------------------------------------
    procedure CAN_wait_frame_sent(
        constant ID             : in    natural range 0 to 15;
        signal   mem_bus        : inout Avalon_mem_type
    );


    ----------------------------------------------------------------------------
    -- Waits until CAN bus becomes idle (no frame in progress).
    -- 
    -- Procedure is polling on status of CTU CAN FD Core over Avalon bus!
    --
    -- Arguments:
    --  ID              Index of CTU CAN FD Core instance
    --  mem_bus         Avalon memory bus to execute the access on.
    ----------------------------------------------------------------------------
    procedure CAN_wait_bus_idle(
        constant ID             : in    natural range 0 to 15;
        signal   mem_bus        : inout Avalon_mem_type
    );


    ----------------------------------------------------------------------------
    -- Waits until CAN bus becomes idle (no frame in progress).
    --
    -- Procedure is polling on status of CTU CAN FD Core over Avalon bus!
    -- 
    -- Arguments:
    --  ID              Index of CTU CAN FD Core instance
    --  mem_bus         Avalon memory bus to execute the access on.
    ----------------------------------------------------------------------------
    procedure CAN_wait_error_transmitted(
        constant ID             : in    natural range 0 to 15;
        signal   mem_bus        : inout Avalon_mem_type
    );
  

    ----------------------------------------------------------------------------
    -- Calculate length of CAN Frame in bits (stuff bits not included).
    -- 
    -- Arguments:
    --  frame           CAN Frame whose length should be calculated.
    --  bit_length      Variable in which the length of CAN Frame in bits is
    --                  stored.
    ----------------------------------------------------------------------------
    procedure CAN_calc_frame_length(
        constant frame          : in    SW_CAN_frame_type;
        variable bit_length     : inout natural
    );
    
  
    function CAN_add_unsigned(
        operator1               : in    std_logic_vector(11 downto 0);
        operator2               : in    std_logic_vector(11 downto 0)
    ) return std_logic_vector;


    ----------------------------------------------------------------------------
    -- Give command to TXT Buffer.
    -- 
    -- Arguments:
    --  cmd             Command to give to TXT Buffer.
    --  buf_index       Number of TXT Buffer which should receive the command.
    --  ID              Index of CTU CAN FD Core instance.
    --  mem_bus         Avalon memory bus to execute the access on.
    ----------------------------------------------------------------------------
    procedure send_TXT_buf_cmd(
        constant cmd            : in    SW_TXT_Buffer_command_type;
        constant buf_n          : in    natural range 1 to 4;
        constant ID             : in    natural range 0 to 15;
        signal   mem_bus        : inout Avalon_mem_type
    );


    ----------------------------------------------------------------------------
    -- Read state of TXT Buffer.
    -- 
    -- Arguments:
    --  buf_index       TXT Buffer number.
    --  retVal          Variable in which return state of the buffer will be
    --                  returned.
    --  ID              Index of CTU CAN FD Core instance.    
    --  mem_bus         Avalon memory bus to execute the access on.
    ---------------------------------------------------------------------------- 
    procedure get_tx_buf_state(
        constant buf_n          : in    natural range 1 to 4;
        variable retVal         : out   SW_TXT_Buffer_state_type;
        constant ID             : in    natural range 0 to 15;
        signal   mem_bus        : inout Avalon_mem_type
    );


    ----------------------------------------------------------------------------
    -- Read version register and return the actual version of the core like so:
    --  MAJOR_VERSION * 10 + MINOR_VERSION.
    -- 
    -- Arguments:
    --  retVal          Variable in which return version will be returned.
    --  ID              Index of CTU CAN FD Core instance.    
    --  mem_bus         Avalon memory bus to execute the access on.
    ---------------------------------------------------------------------------- 
    procedure get_core_version(
        variable retVal         : out   natural;
        constant ID             : in    natural range 0 to 15;
        signal   mem_bus        : inout Avalon_mem_type
    );




    ----------------------------------------------------------------------------
    ----------------------------------------------------------------------------
    -- sanity test Stuff; must be in a package
    ----------------------------------------------------------------------------
    ----------------------------------------------------------------------------
    constant NODE_COUNT : natural := 4;
    type bus_matrix_type is array(1 to NODE_COUNT,1 to NODE_COUNT) of real;
    type anat_t is array (integer range <>) of natural;
    subtype anat_nc_t is anat_t (1 to NODE_COUNT);

    subtype epsilon_type is anat_nc_t;
    subtype trv_del_type is anat_nc_t;
    subtype timing_config_t is anat_t(1 to 10);
  

    ----------------------------------------------------------------------------
    ----------------------------------------------------------------------------
    -- Component declarations
    ----------------------------------------------------------------------------
    ----------------------------------------------------------------------------
    component CAN_test is
    port (
        signal run            :in   boolean;
        signal iterations     :in   natural;
        signal log_level      :in   log_lvl_type;
        signal error_beh      :in   err_beh_type;
        signal error_tol      :in   natural;
        signal status         :out  test_status_type;
        signal errors         :out  natural 
    );
    end component;
  
end package;




--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Library implementation
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

package body CANtestLib is


    procedure evaluate_test(
        signal error_th         : in    natural;
        signal errors           : in    natural;
        signal status           : out   test_status_type
    ) is
    begin

        -- Evaluate the test result
        if (errors < error_th or errors = error_th) then
            status    <= passed;
            wait for 200 ns;
            report "Test result: SUCCESS" severity note; 
        else
            status    <= failed;
            wait for 200 ns;
            report "Test result: FAILURE" severity error; 
        end if;

        -- Finish the test
        wait for 200 ns;
        report "Test END" severity failure;

    end procedure;


    procedure generate_clock(
        constant period         : in    natural;
        constant duty           : in    natural;
        constant epsilon_ppm    : in    natural;
        signal   out_clk        : out   std_logic
    ) is
        variable real_period    :       real;
        variable rand_nr        :       real;
        variable high_per       :       real;
        variable low_per        :       real;
        variable high_time      :       time;
        variable low_time       :       time;
    begin
  
        -- If clock has uncertainty then it is constantly added to the clock!
        -- This covers the worst case!!
        real_period   := real(period) + 
                         (real(period * epsilon_ppm)) / 1000000.0;
        high_per      := ((real(duty)) * real_period) / 100.0;
        low_per       := ((real(100-duty)) * real_period) / 100.0;
        high_time     := integer(high_per * 1000.0) * 1 ns;
        high_time     := high_time / 1000000;
        low_time      := integer(low_per * 1000.0) * 1 ns;
        low_time      := low_time / 1000000;

        --Generate the clock itself
        out_clk       <= '1';
        wait for high_time;
        out_clk       <= '0';
        wait for low_time;
  
    end procedure;


    function CAN_add_unsigned(
        operator1               : in    std_logic_vector(11 downto 0);
        operator2               : in    std_logic_vector(11 downto 0)
    ) return std_logic_vector is
    begin
        return std_logic_vector(unsigned(operator1) + unsigned(operator2));
    end function;


    procedure log(
        constant Message        : in    String;
        constant log_severity   : in    log_lvl_type;
        signal log_level        : in    log_lvl_type
   )is
    begin 
  
    if (log_level = info_l) then
        if (log_severity = info_l) then
            report Message severity NOTE;
        elsif (log_severity = warning_l)then
            report Message severity WARNING;
        elsif (log_severity = error_l) then
            report Message severity ERROR; 
        else
            report "Unsupported log severity type in 'log' function"
            severity failure;
        end if;

    elsif (log_level = warning_l) then

        if (log_severity = warning_l) then
            report Message severity WARNING;
        elsif (log_severity = error_l) then
            report Message severity ERROR; 
        end if;

    elsif (log_level = error_l) then

        if (log_severity = error_l) then
            report Message severity ERROR; 
        end if;

    else
        report "Unsupported severity type in 'log' function" severity failure;
    end if;

    end procedure;


    procedure reset_test(
        signal res_n            : out   std_logic;
        signal status           : out   test_status_type;
        signal run              : in    boolean;
        signal error_ctr        : out   natural
        )is
    begin
        res_n     <= '0';
        status    <= waiting;

        wait for 100 ns;
        while run = false loop
            wait for 10 ns;
        end loop;

        res_n     <= '1';
        status    <= running;
        error_ctr <= 0;
        wait for 250 ns;
    end procedure;


    procedure process_error(
        signal error_ctr        : inout natural;
        signal error_beh        : in    err_beh_type;
        signal exit_imm         : out   boolean
    )is
    begin
        error_ctr       <= error_ctr + 1;

        if (error_beh = quit) then
            exit_imm    <= true;
        else
            exit_imm    <= false;
        end if;
        
        wait for 0 ns;
    end procedure;


    procedure print_test_info(
        signal iterations       :in    natural;
        signal log_level        :in    log_lvl_type;
        signal error_beh        :in    err_beh_type;
        signal error_tol        :in    natural
    )is
    begin
        report "Test info:";
        report "Number of iterations: " & integer'image(iterations);

        if (log_level = info_l) then 
            report "Log level: INFO,WARNING,ERROR logs are shown!";
        elsif (log_level = warning_l) then
            report "Log level: WARNING,ERROR logs are shown!";
        else
            report "Log level: ERROR logs are shown!";
        end if;

        if (error_beh = go_on) then    
            report "When error is detected test runs on";
        else
            report "When error is detected test quits";
        end if;
          
        report "Error tolerance: " & integer'image(error_tol);
    end;


    procedure decode_dlc(
        signal   dlc            : in    std_logic_vector(3 downto 0);
        variable length         : out   natural
    )is 
    begin
        case dlc is
        when "0000" => length := 0;
        when "0001" => length := 1;
        when "0010" => length := 2;
        when "0011" => length := 3;
        when "0100" => length := 4;  
        when "0101" => length := 5;  
        when "0110" => length := 6;  
        when "0111" => length := 7;
        when "1000" => length := 8;
        when "1001" => length := 12;
        when "1010" => length := 16;
        when "1011" => length := 20;
        when "1100" => length := 24;
        when "1101" => length := 32;
        when "1110" => length := 48;
        when "1111" => length := 64;
        when others => length := 0;
        end case;  
    end procedure;


    procedure decode_dlc_v(
        constant dlc            : in    std_logic_vector(3 downto 0);
        variable length         : out   natural
    )is 
    begin
        case dlc is
        when "0000" => length := 0;
        when "0001" => length := 1;
        when "0010" => length := 2;
        when "0011" => length := 3;
        when "0100" => length := 4;  
        when "0101" => length := 5;  
        when "0110" => length := 6;  
        when "0111" => length := 7;
        when "1000" => length := 8;
        when "1001" => length := 12;
        when "1010" => length := 16;
        when "1011" => length := 20;
        when "1100" => length := 24;
        when "1101" => length := 32;
        when "1110" => length := 48;
        when "1111" => length := 64;
        when others => length := 0;
        end case;
    end procedure;


    procedure decode_dlc_rx_buff(
        constant dlc            : in    std_logic_vector(3 downto 0);
        variable rwcnt          : out   natural
    )is 
    begin
        case dlc is
        when "0000" => rwcnt := 3;
        when "0001" => rwcnt := 4;
        when "0010" => rwcnt := 4;
        when "0011" => rwcnt := 4;
        when "0100" => rwcnt := 4;  
        when "0101" => rwcnt := 5;  
        when "0110" => rwcnt := 5;  
        when "0111" => rwcnt := 5;
        when "1000" => rwcnt := 5;
        when "1001" => rwcnt := 6;
        when "1010" => rwcnt := 7;
        when "1011" => rwcnt := 8;
        when "1100" => rwcnt := 9;
        when "1101" => rwcnt := 11;
        when "1110" => rwcnt := 15;
        when "1111" => rwcnt := 19;
        when others => rwcnt := 0;
        end case;  
    end procedure;


    procedure decode_dlc_buff(
        signal   dlc            : in    std_logic_vector(3 downto 0);
        variable buff_space     : out   natural
    )is
    begin
        case dlc is
        when "0000" => buff_space := 0 + 4; --Zero bits
        when "0001" => buff_space := 1 + 4; --1 byte
        when "0010" => buff_space := 1 + 4; --2 bytes
        when "0011" => buff_space := 1 + 4; --3 bytes
        when "0100" => buff_space := 1 + 4; --4 bytes
        when "0101" => buff_space := 2 + 4; --5 bytes
        when "0110" => buff_space := 2 + 4; --6 bytes
        when "0111" => buff_space := 2 + 4; --7 bytes
        when "1000" => buff_space := 2 + 4; --8 bytes
        when "1001" => buff_space := 3 + 4; --12 bytes
        when "1010" => buff_space := 4 + 4; --16 bytes
        when "1011" => buff_space := 5 + 4; --20 bytes
        when "1100" => buff_space := 6 + 4; --24 bytes
        when "1101" => buff_space := 8 + 4; --32 bytes
        when "1110" => buff_space := 12 + 4; --48 bytes
        when "1111" => buff_space := 16 + 4; --64 bytes
        when others => buff_space := 0;
        end case;
    end procedure;


    procedure generate_simple_trig(
        signal   rand_ctr       : inout natural range 0 to RAND_POOL_SIZE;
        signal   sync           : out   std_logic;
        signal   sample         : out   std_logic;
        signal   clk_sys        : in    std_logic;
        variable min_diff       : in    natural
    )is
        variable diff           :       real;
        variable round          :       natural;
    begin
        wait until rising_edge(clk_sys);
        sample      <=  '0';
        wait until rising_edge(clk_sys);
        wait until rising_edge(clk_sys);
        sync        <=  '1';

        rand_real_v(rand_ctr, diff);
        diff := 10.0 * diff;
        if (integer(diff) < min_diff) then
          diff := real(min_diff);
        end if;
        round := integer(diff);

        for i in 0 to round loop
            wait until rising_edge(clk_sys);

            if (i = 0) then
                sync <= '0';
            end if;

            if (i = round) then
                sample <= '1';
            end if;
        end loop;
    end procedure;


    procedure generate_trig(
        signal    sync            : out     std_logic;
        signal    sample          : out     std_logic;
        signal    clk_sys         : in      std_logic;
        signal    seg1            : in      natural;
        signal    seg2            : in      natural
    )is
    begin
        wait until rising_edge(clk_sys);
        sync <= '1';
        wait until rising_edge(clk_sys);
        sync <= '0';
        
        for i in 1 to seg1 - 1 loop
            wait until rising_edge(clk_sys);
        end loop;
        
        sample <= '1';
        wait until rising_edge(clk_sys);
        sample <= '0';
        
        for i in 1 to seg2 - 1 loop
            wait until rising_edge(clk_sys);
        end loop;
    end procedure;
  
  
    function aval_is_aligned(
        constant  address       : in    std_logic_vector(23 downto 0);
        constant  size          : in    aval_access_size
    )return boolean is
    begin
        case size is
        when BIT_8 =>
            return true;
        when BIT_16 =>
            if (address(0) = '1') then
                return true;
            else
                return false;
            end if;
        when BIT_32 =>
            if (address(1 downto 0) = "00") then
                return true;
            else
                return false;
            end if;
        when others => 
            return false;
        end case;
    end function;


    function bsize_to_be(
        constant address       : in    std_logic_vector(23 downto 0);
        constant size          : in    aval_access_size
    ) return std_logic_vector is
    begin
        if (size = BIT_32) then
            return "1111";
        end if;

        if (size = BIT_16) then
            if (address (1) = '0') then
                return "1100";
            else
                return "0011";
            end if;
        end if;

        if (size = BIT_8) then
            case address(1 downto 0) is
            when "00"   => return "0001";
            when "01"   => return "0010";
            when "10"   => return "0100";
            when "11"   => return "1000";
            when others => return "0000";
            end case;
        end if;
    end function;


    procedure aval_write(
        constant  w_data        : in    std_logic_vector(31 downto 0);
        constant  w_address     : in    std_logic_vector(23 downto 0);
        constant  w_size        : in    aval_access_size;
        signal    mem_bus       : inout Avalon_mem_type
    )is
        variable msg            :       line;
    begin

        -- Check for access alignment
        if (not aval_is_aligned(w_address, w_size)) then
            write(msg, string'("Unaligned Avalon write, Adress :"));            
            hwrite(msg, w_address);
            write(msg, string'(" Size: "));
            write(msg, aval_access_size'image(w_size)); 
            writeline(output, msg);
        else
            wait until falling_edge(mem_bus.clk_sys);
            mem_bus.scs       <=  '1';
            mem_bus.swr       <=  '1';
            mem_bus.sbe       <=  bsize_to_be(w_address, w_size);

            -- Align the adress for the Core!
            mem_bus.address   <=  w_address(23 downto 2) & "00";
            mem_bus.data_in   <=  w_data;

            wait until falling_edge(mem_bus.clk_sys);
            mem_bus.scs       <=  '0';
            mem_bus.swr       <=  '0';
            mem_bus.sbe       <=  (OTHERS => '0');
            mem_bus.address   <=  (OTHERS => '0');
            mem_bus.data_in   <=  (OTHERS => '0');
        end if;

    end procedure;


    procedure aval_read(
        variable  r_data        : out   std_logic_vector(31 downto 0);
        constant  r_address     : in    std_logic_vector(23 downto 0);
        constant  r_size        : in    aval_access_size;
        signal    mem_bus       : inout Avalon_mem_type
    )is
        variable  msg           :       line;
    begin

        -- Check for access alignment
        if (not aval_is_aligned(r_address, r_size)) then
            write(msg, string'("Unaligned Avalon Read, Adress :"));            
            hwrite(msg, r_address);
            write(msg, string'(" Size: "));
            write(msg, aval_access_size'image(r_size)); 
            writeline(output, msg);
        else
            wait until falling_edge(mem_bus.clk_sys);
            mem_bus.scs       <=  '1';
            mem_bus.srd       <=  '1';
            mem_bus.sbe       <=  bsize_to_be(r_address, r_size);

            -- Align the adress for the Core!
            mem_bus.address   <=  r_address(23 downto 2) & "00";

            wait until falling_edge(mem_bus.clk_sys);
            r_data            :=  mem_bus.data_out;
            mem_bus.scs       <=  '0';
            mem_bus.srd       <=  '0';
            mem_bus.sbe       <=  (OTHERS => '0');
            mem_bus.address   <=  (OTHERS => '0');
        end if;

    end procedure;


    procedure CAN_write(
        constant  w_data        : in    std_logic_vector(31 downto 0);
        constant  w_offset      : in    std_logic_vector(11 downto 0);
        constant  ID            : in    natural range 0 to 15;
        signal    mem_bus       : inout Avalon_mem_type;
        constant  w_size        : in    aval_access_size := BIT_32
    )is
        variable int_address   :   std_logic_vector(23 downto 0);
    begin
        int_address       := CAN_COMPONENT_TYPE &
                             std_logic_vector(to_unsigned(ID, 4)) &
                             "0000" & w_offset;
        aval_write(w_data, int_address, w_size, mem_bus);
    end procedure;
  

    procedure CAN_read(
        variable  r_data        : out   std_logic_vector(31 downto 0);
        constant  r_offset      : in    std_logic_vector(11 downto 0);
        constant  ID            : in    natural range 0 to 15;
        signal    mem_bus       : inout Avalon_mem_type;
        constant  r_size        : in    aval_access_size := BIT_32
    )is
        variable int_address   :   std_logic_vector(23 downto 0);
    begin
        int_address       := CAN_COMPONENT_TYPE &
                             std_logic_vector(to_unsigned(ID, 4)) &
                             "0000" & r_offset;
        aval_read(r_data, int_address, r_size, mem_bus);
    end procedure;
 

    procedure CAN_configure_timing(
        constant bus_timing     : in    bit_time_config_type;
        constant ID             : in    natural range 0 to 15;
        signal   mem_bus        : inout Avalon_mem_type    
    )is
        variable data           :       std_logic_vector(31 downto 0) :=
                                        (OTHERS => '0');
    begin
     
        -- Bit timing register - Nominal
        data(BRP_H downto BRP_L) := std_logic_vector(to_unsigned(
                bus_timing.tq_nbt, BRP_H - BRP_L + 1));
        data(PROP_H downto PROP_L) := std_logic_vector(to_unsigned(
                bus_timing.prop_nbt, PROP_H - PROP_L + 1));
        data(PH1_H downto PH1_L) := std_logic_vector(to_unsigned(
                bus_timing.ph1_nbt, PH1_H - PH1_L + 1));
        data(PH2_H downto PH2_L) := std_logic_vector(to_unsigned(
                bus_timing.ph2_nbt, PH2_H - PH2_L + 1));
        data(SJW_H downto SJW_L) := std_logic_vector(to_unsigned(
                bus_timing.sjw_nbt, SJW_H - SJW_L + 1));
        CAN_write(data, BTR_ADR, ID, mem_bus);     

        -- Bit timing register - Data
        data(BRP_FD_H downto BRP_FD_L) := std_logic_vector(to_unsigned(
                bus_timing.tq_dbt, BRP_FD_H - BRP_FD_L + 1));
        data(PROP_FD_H downto PROP_FD_L) := std_logic_vector(to_unsigned(
                bus_timing.prop_dbt, PROP_FD_H - PROP_FD_L + 1));
        data(PH1_FD_H downto PH1_FD_L) := std_logic_vector(to_unsigned(
                bus_timing.ph1_dbt, PH1_FD_H - PH1_FD_L + 1));
        data(PH2_FD_H downto PH2_FD_L) := std_logic_vector(to_unsigned(
                bus_timing.ph2_dbt, PH2_FD_H - PH2_FD_L + 1));
        data(SJW_FD_H downto SJW_FD_L) := std_logic_vector(to_unsigned(
                bus_timing.sjw_dbt, SJW_FD_H - SJW_FD_L + 1));
        CAN_write(data, BTR_FD_ADR, ID, mem_bus);
    end procedure;
  
  
    procedure CAN_read_timing(
        signal   bus_timing     : out   bit_time_config_type;
        constant ID             : in    natural range 0 to 15;
        signal   mem_bus        : inout Avalon_mem_type    
    )is
        variable data           :       std_logic_vector(31 downto 0);
    begin

        -- Bit timing register - Nominal
        CAN_read(data, BTR_ADR, ID, mem_bus);
        bus_timing.tq_nbt    <= to_integer(unsigned(data(BRP_H downto BRP_L)));
        bus_timing.prop_nbt  <= to_integer(unsigned(data(PROP_H downto PROP_L)));
        bus_timing.ph1_nbt   <= to_integer(unsigned(data(PH1_H downto PH1_L)));
        bus_timing.ph2_nbt   <= to_integer(unsigned(data(PH2_H downto PH2_L)));
        bus_timing.sjw_nbt   <= to_integer(unsigned(data(SJW_H downto SJW_L)));

        -- Bit timing register - Data
        CAN_read(data, BTR_FD_ADR, ID, mem_bus);
        bus_timing.tq_dbt    <= to_integer(unsigned(data(BRP_FD_H downto
                                                         BRP_FD_L)));
        bus_timing.prop_dbt  <= to_integer(unsigned(data(PROP_FD_H downto
                                                         PROP_FD_L)));
        bus_timing.ph1_dbt   <= to_integer(unsigned(data(PH1_FD_H downto
                                                         PH1_FD_L)));
        bus_timing.ph2_dbt   <= to_integer(unsigned(data(PH2_FD_H downto
                                                         PH2_FD_L)));
        bus_timing.sjw_dbt   <= to_integer(unsigned(data(SJW_FD_H downto
                                                         SJW_FD_L)));
    end procedure;


    procedure CAN_turn_controller(
        constant turn_on        : in    boolean;
        constant ID             : in    natural range 0 to 15;
        signal   mem_bus        : inout Avalon_mem_type    
    )is
        variable data           :       std_logic_vector(31 downto 0) :=
                                        (OTHERS => '0');
    begin
        CAN_read(data, MODE_ADR, ID, mem_bus);
        if turn_on then
            data(ENA_IND) := ENABLED;
        else
            data(ENA_IND) := DISABLED;
        end if;
        CAN_write(data, MODE_ADR, ID, mem_bus);  
    end procedure;
  
   
    procedure CAN_enable_retr_limit(
        constant enable         : in    boolean;
        constant limit          : in    natural range 0 to 15;
        constant ID             : in    natural range 0 to 15;
        signal   mem_bus        : inout Avalon_mem_type    
    )is
        variable data           :       std_logic_vector(31 downto 0) :=
                                        (OTHERS => '0');
    begin
        CAN_read(data, MODE_ADR, ID, mem_bus);
        if enable then
            data(RTRLE_IND) := '1';
        else
            data(RTRLE_IND) := '0';
        end if;
        data(RTR_TH_H downto RTR_TH_L) := std_logic_vector(to_unsigned(limit, 4));
        CAN_write(data, MODE_ADR, ID, mem_bus);
    end procedure;


    procedure CAN_generate_frame(
        signal   rand_ctr       : inout natural range 0 to RAND_POOL_SIZE;
        variable frame          : inout SW_CAN_frame_type
    )is
        variable rand_value     : real := 0.0;
        variable aux            : std_logic_vector(28 downto 0);
    begin
       
        rand_logic_v(rand_ctr, frame.ident_type, 0.5);
        rand_logic_v(rand_ctr, frame.frame_format, 0.5);
        rand_logic_v(rand_ctr, frame.rtr, 0.5);
        rand_logic_v(rand_ctr, frame.brs, 0.5);
        rand_logic_vect_v(rand_ctr, frame.data, 0.5);
        rand_logic_vect_v(rand_ctr, frame.dlc, 0.3);

        rand_real_v(rand_ctr, rand_value);

        -- We generate only valid frame combinations to avoid problems...
        -- FD frames has no RTR frame, neither the RTR field!
        if (frame.frame_format = FD_CAN) then
            frame.rtr := NO_RTR_FRAME;
        end if;

        if (frame.frame_format = NORMAL_CAN) then
            frame.brs := BR_NO_SHIFT;
        end if; 

        -- If base identifier, the lowest bits of unsigned ID contain the
        -- basic value!
        aux := (OTHERS => '0');
        if (frame.ident_type = BASE) then
            rand_value          := rand_value * 2047.0;
            aux(10 downto 0)    := std_logic_vector(
                                   to_unsigned(integer(rand_value), 11)); 
        else
            rand_value          := rand_value * 536870911.0;
            aux(28 downto 0)    := std_logic_vector(
                                   to_unsigned(integer(rand_value), 29)); 
        end if;
        frame.identifier := to_integer(unsigned(aux));

        decode_dlc_v(frame.dlc, frame.data_length);
        frame.timestamp := (OTHERS => '0');

        if (frame.rtr = RTR_FRAME) then
            frame.data          := (OTHERS => '0');
            frame.dlc           := (OTHERS => '0');
            frame.data_length   := 0;
        end if;

        -- RWCNT is filled to have all information in the frame
        -- as is filled by the RX Buffer.
        decode_dlc_rx_buff(frame.dlc, frame.rwcnt);

        -- Unused bytes of data can be set to 0
        frame.data(511 - frame.data_length * 8 downto 0) := (OTHERS => '0');
    end procedure;
  


    procedure CAN_compare_frames(
        constant frame_A        : in    SW_CAN_frame_type;
        constant frame_B        : in    SW_CAN_frame_type;
        constant comp_ts        : in    boolean;
        variable outcome        : inout boolean
    )is
    begin
        outcome := true;
    
        if (frame_A.frame_format /= frame_B.frame_format) then
            outcome := false;
        end if;
    
        if (frame_A.ident_type /= frame_B.ident_type) then
            outcome := false;
        end if;
    
        -- RTR should be te same only in normal CAN Frame. In FD Frame there is
        -- no RTR bit!
        if (frame_A.frame_format = NORMAL_CAN) then
            if (frame_A.rtr /= frame_B.rtr) then
                outcome := false;
            end if;
        end if;
    
        -- BRS bit is compared only in FD frame
        if (frame_A.frame_format = FD_CAN) then
            if (frame_A.brs /= frame_B.brs) then
                outcome := false;
            end if;
        end if;
    
        -- Received word count
        if (frame_A.rwcnt /= frame_B.rwcnt) then
            outcome := false;
        end if;
    
        -- DLC is compared only in non-RTR frames!
        -- In RTR frames it does not necessarily have to be equal due to 
        -- RTR-pref feature (though it should be zero in normal controllers).
        if ((frame_A.rtr = NO_RTR_FRAME or frame_A.frame_format = FD_CAN)
            and (frame_A.dlc /= frame_B.dlc))
        then
            outcome := false;
        end if;

        if (frame_A.identifier /= frame_B.identifier) then
            outcome := false;
        end if;

        -- Compare data for NON-RTR Frames. To save time comparing frames whose
        -- metadata comparison failed, do it only for frames which are fine till
        -- now.
        if (outcome = true) then
            if ((frame_A.rtr = NO_RTR_FRAME or frame_A.frame_format = FD_CAN)
                and frame_A.data_length /= 0)
            then
                for i in 0 to (frame_A.data_length - 1) / 4 loop
                    if (frame_A.data(511 - i * 32 downto 480 - i * 32) /=
                        frame_B.data(511 - i * 32 downto 480 - i * 32))
                    then
                        outcome  := false;
                    end if;
                end loop;
            end if;
        end if;
    end procedure;


    procedure CAN_send_frame(
        constant frame          : in    SW_CAN_frame_type;
        constant buf_nr         : in    natural range 1 to 4;
        constant ID             : in    natural range 0 to 15;
        signal   mem_bus        : inout Avalon_mem_type;
        variable outcome        : out   boolean
    )is
        variable w_data         :       std_logic_vector(31 downto 0) :=
                                        (OTHERS => '0');
        variable ident_vect     :       std_logic_vector(28 downto 0) :=
                                        (OTHERS => '0');
        variable length         :       natural;
        variable iter_limit     :       natural;
        variable aux_out        :       boolean;
        variable buf_index      :       natural range 0 to 31;
        variable buf_state      :       SW_TXT_Buffer_state_type;
        variable bind_int       :       natural;
        variable buf_offset     :       std_logic_vector(11 downto 0);
    begin
        outcome     := true;

        -- Read Status of TXT Buffer.
        get_tx_buf_state(buf_nr, buf_state, ID, mem_bus);

        -- If TXT Buffer was already locked -> Fail to insert and transmitt!
        if (buf_state = buf_tx_progress or
            buf_state = buf_ab_progress or
            buf_state = buf_ready)
        then
            report "Unable to send the frame, TXT buffer is READY, " &
                   "TX is in progress, or Abort is in progress" severity error;
            outcome     := false;
            return;
        end if;

        -- Set Buffer address
        case buf_nr is
        when 1 => buf_offset := TXTB1_DATA_1_ADR;
        when 2 => buf_offset := TXTB2_DATA_1_ADR;
        when 3 => buf_offset := TXTB3_DATA_1_ADR;
        when 4 => buf_offset := TXTB4_DATA_1_ADR;
        when others =>
            report "Unsupported TX buffer number" severity error;
        end case;
          
        -- Frame format word
        w_data                      := (OTHERS => '0');
        w_data(DLC_H downto DLC_L)  := frame.dlc;
        w_data(RTR_IND)             := frame.rtr;
        w_data(ID_TYPE_IND)         := frame.ident_type;
        w_data(FR_TYPE_IND)         := frame.frame_format;
        w_data(TBF_IND)             := '1';
        w_data(BRS_IND)             := frame.brs;
        w_data(ESI_RESVD_IND)       := '0'; -- ESI is receive only
        CAN_write(w_data, buf_offset, ID, mem_bus);          
             
        -- Identifier
        w_data := (OTHERS => '0');
        if (frame.ident_type = EXTENDED) then
            if (frame.identifier > 536870911) then
                report "Extended Identifier Exceeds the maximal value!"
                severity error;
            end if;
            ident_vect := std_logic_vector(to_unsigned(frame.identifier, 29));
            w_data(IDENTIFIER_BASE_H downto IDENTIFIER_BASE_L) := 
                ident_vect(28 downto 18);
            w_data(IDENTIFIER_EXT_H downto IDENTIFIER_EXT_L) := 
                ident_vect(17 downto 0);
        else
            if (frame.identifier > 2047) then
                report "Base Identifier Exceeds the maximal value!"
                severity error;
            end if;
            ident_vect := "000000000000000000" & 
                           std_logic_vector(to_unsigned(frame.identifier, 11));
            w_data(IDENTIFIER_BASE_H downto IDENTIFIER_BASE_L) :=
                ident_vect(10 downto 0);
        end if;
        CAN_write(w_data, CAN_add_unsigned(buf_offset, IDENTIFIER_W_ADR),
                  ID, mem_bus);

        -- Timestamp
        w_data := frame.timestamp(31 downto 0);  
        CAN_write(w_data, CAN_add_unsigned(buf_offset, TIMESTAMP_L_W_ADR),
                  ID, mem_bus);
        w_data := frame.timestamp(63 downto 32);  
        CAN_write(w_data, CAN_add_unsigned(buf_offset, TIMESTAMP_U_W_ADR),
                  ID, mem_bus);

        -- Data words
        decode_dlc_v(frame.dlc, length);
        for i in 0 to (length - 1) / 4 loop
            w_data:= frame.data(511 - i * 32 downto 480 - i * 32);
            CAN_write(w_data, std_logic_vector(unsigned(buf_offset) +
                              unsigned(DATA_1_4_W_ADR) + i * 4),
                      ID, mem_bus);
        end loop;

        -- Give "Set ready" command to the buffer
        send_TXT_buf_cmd(buf_set_ready, buf_nr, ID, mem_bus);
    end procedure;
  

    procedure CAN_read_frame(
        variable frame          : inout SW_CAN_frame_type;
        constant ID             : in    natural range 0 to 15;
        signal   mem_bus        : inout Avalon_mem_type
    )is
        variable r_data         :       std_logic_vector(31 downto 0) :=
                                        (OTHERS => '0');
        variable aux_vect       :       std_logic_vector(28 downto 0) :=
                                        (OTHERS => '0');
    begin
        -- Read Frame format word
        CAN_read(r_data, RX_DATA_ADR, ID, mem_bus);   
        frame.dlc           := r_data(DLC_H downto DLC_L);
        frame.rtr           := r_data(RTR_IND);
        frame.ident_type    := r_data(ID_TYPE_IND);
        frame.frame_format  := r_data(FR_TYPE_IND);
        frame.brs           := r_data(BRS_IND);
        frame.rwcnt         := to_integer(unsigned(
                               r_data(RWCNT_H downto RWCNT_L)));
        decode_dlc_v(frame.dlc, frame.data_length);

        --Read identifier
        CAN_read(r_data, RX_DATA_ADR, ID, mem_bus);
        if (frame.ident_type = EXTENDED) then
            aux_vect         := r_data(IDENTIFIER_BASE_H downto 
                                       IDENTIFIER_BASE_L) &
                                r_data(IDENTIFIER_EXT_H downto 
                                       IDENTIFIER_EXT_L);
            frame.identifier := to_integer(unsigned(aux_vect));
        else
          aux_vect         := "000000000000000000" &
                              r_data(IDENTIFIER_BASE_H downto IDENTIFIER_BASE_L);
          frame.identifier := to_integer(unsigned(aux_vect));
        end if;

        -- Read timestamp
        CAN_read(r_data, RX_DATA_ADR, ID, mem_bus);  
        frame.timestamp(31 downto 0)  := r_data;
        CAN_read(r_data,RX_DATA_ADR,ID,mem_bus);  
        frame.timestamp(63 downto 32) := r_data;

        -- Now read data frames
        if ((frame.rtr = NO_RTR_FRAME or frame.frame_format = FD_CAN) 
             and frame.data_length /= 0)
        then
            for i in 0 to (frame.data_length - 1) / 4 loop
                CAN_read(r_data, RX_DATA_ADR, ID, mem_bus);
                frame.data(511 - i * 32 downto 480 - i * 32) := r_data;
            end loop;
        end if;
    end procedure;
  

    procedure CAN_wait_frame_sent(
        constant ID             : in    natural range 0 to 15;
        signal   mem_bus        : inout Avalon_mem_type
    )is
        variable r_data         :       std_logic_vector(31 downto 0) :=
                                        (OTHERS => '0');
    begin
     
        -- Wait until unit starts to transmitt or reciesve
        CAN_read(r_data, MODE_ADR, ID, mem_bus);
        while (r_data(RS_IND) = '0' and r_data(TS_IND) = '0') loop
            CAN_read(r_data, MODE_ADR, ID, mem_bus);
        end loop;

        -- Wait until bus is idle now
        CAN_read(r_data, MODE_ADR, ID, mem_bus);
        while (r_data(BS_IND) = '0') loop
            CAN_read(r_data, MODE_ADR, ID, mem_bus);
        end loop;
     
    end procedure;
  

    procedure CAN_wait_bus_idle(
        constant ID             : in    natural range 0 to 15;
        signal   mem_bus        : inout Avalon_mem_type
    )is
        variable r_data         :       std_logic_vector(31 downto 0) :=
                                        (OTHERS => '0');
    begin
        -- Wait until bus is idle
        CAN_read(r_data, MODE_ADR, ID, mem_bus);
        while (r_data(BS_IND) = '0') loop
            CAN_read(r_data, MODE_ADR, ID, mem_bus);
        end loop;
    end procedure;


    procedure CAN_wait_error_transmitted(
        constant ID             : in    natural range 0 to 15;
        signal   mem_bus        : inout Avalon_mem_type
    )is
        variable r_data         :       std_logic_vector(31 downto 0) :=
                                        (OTHERS => '0');
    begin
     
     -- Wait until unit starts to transmitt or recieve
     CAN_read(r_data, MODE_ADR, ID, mem_bus);
     while (r_data(RS_IND) = '0' and r_data(TS_IND) = '0') loop
        CAN_read(r_data, MODE_ADR, ID, mem_bus);
     end loop;
     
     -- Wait until error frame is not being transmitted
     CAN_read(r_data, MODE_ADR, ID, mem_bus);
     while (r_data(ET_IND) = '0') loop
        CAN_read(r_data, MODE_ADR, ID, mem_bus);
     end loop;
     
    end procedure;
  

    procedure CAN_calc_frame_length(
        constant frame          : in    SW_CAN_frame_type;
        variable bit_length     : inout natural
    )is
        variable aux            :       std_logic_vector(1 downto 0);
        variable data_length    :       natural;
    begin
        decode_dlc_v(frame.dlc, data_length);
        if (frame.rtr = RTR_FRAME and frame.frame_format = NORMAL_CAN) then
            data_length := 0;
        end if;

        -- Join the ident type and frame type
        aux:= frame.ident_type & frame.frame_format;

        -- Calculated identifer and control length
        case aux is
        when "00" =>
            bit_length := 18;
        when "01" =>   
            bit_length := 23;
        when "10" =>   
            bit_length := 39;   
        when "11" =>   
            bit_length := 41;
        when others =>
        end case; 

        -- Add the data length field    
        bit_length := bit_length + data_length;

        -- Add CRC
        if (data_length < 9) then
            bit_length := bit_length + 15;
        elsif (data_length < 17) then
            bit_length := bit_length + 17;
        else
            bit_length := bit_length + 21;
        end if;

        -- Add CRC delimiter, Acknowledge and Acknowledge delimiter
        bit_length := bit_length + 3;
    end procedure;
 

    procedure send_TXT_buf_cmd(
        constant cmd            : in    SW_TXT_Buffer_command_type;
        constant buf_n          : in    natural range 1 to 4;
        constant ID             : in    natural range 0 to 15;
        signal   mem_bus        : inout Avalon_mem_type
    )is
        variable data           :         std_logic_vector(31 downto 0);
    begin
        -- Set active command bit in TX_COMMAND register based on input command
        data(TXCE_IND) := '0';
        data(TXCR_IND) := '0';
        data(TXCA_IND) := '0';
        if (cmd = buf_set_empty) then
            data(TXCE_IND) := '1';
        elsif (cmd = buf_set_ready) then
            data(TXCR_IND) := '1';
        elsif (cmd = buf_set_abort) then
            data(TXCA_IND) := '1';
        end if;

        -- Set index of Buffer on which the command should be executed.
        data(buf_n + TXI1_IND - 1) := '1';

        -- Give the command
        CAN_write(data, TX_COMMAND_ADR, ID, mem_bus);
    end procedure;
  
  
    procedure get_tx_buf_state(
        constant buf_n          : in    natural range 1 to 4;
        variable retVal         : out   SW_TXT_Buffer_state_type;
        constant ID             : in    natural range 0 to 15;
        signal   mem_bus        : inout Avalon_mem_type
    )is
        variable data           :       std_logic_vector(31 downto 0);
        variable b_state        :       std_logic_vector(3 downto 0);
        variable buf_index      :       natural range 0 to 3;
    begin
        CAN_read(data, TX_STATUS_ADR, ID, mem_bus);
        buf_index := buf_n - 1;
        b_state   := data((buf_index + 1) * 4 - 1 downto buf_index * 4);

        case b_state is
        when TXT_RDY  => retVal := buf_ready;
        when TXT_TRAN => retVal := buf_tx_progress;
        when TXT_ABTP => retVal := buf_ab_progress;
        when TXT_TOK  => retVal := buf_done;
        when TXT_ERR  => retVal := buf_failed;
        when TXT_ABT  => retVal := buf_aborted;
        when TXT_ETY  => retVal := buf_empty;
        when others =>
        report "Invalid TXT Buffer state: " & 
                  integer'image(to_integer(unsigned(b_state))) severity error;  
        end case;

    end procedure;


    procedure get_core_version(
        variable retVal         : out   natural;
        constant ID             : in    natural range 0 to 15;
        signal   mem_bus        : inout Avalon_mem_type
    ) is
        variable data           :       std_logic_vector(31 downto 0);
    begin
        CAN_read(data, VERSION_ADR, ID, mem_bus, BIT_16);

        retVal := (10 * to_integer(unsigned(data(VER_MAJOR_H downto 
                                                 VER_MAJOR_L)))) +
                  to_integer(unsigned(data(VER_MINOR_H downto VER_MINOR_L)));

    end procedure;

end package body;


USE work.CANtestLib.All;

-------------------------------------------------------------
-- Main test entity. Each test of  the unit test environment
-- implements architecture of this entity!       
-------------------------------------------------------------
entity CAN_test is
  port (

    -- Input trigger, test starts running when true
    signal run              :in     boolean;

    -- Number of iterations that test should do
    signal iterations       :in     natural;

    -- Logging level, severity which should be shown
    signal log_level        :in     log_lvl_type;

    -- Test behaviour when error occurs: Quit, or Go on
    signal error_beh        :in     err_beh_type;

    -- Error tolerance, error counter should not
    -- exceed this value in order for the test to pass
    signal error_tol        :in     natural;
                                                 
    -- Status of the test        
    signal status           :out    test_status_type;

    -- Amount of errors which appeared in the test
    signal errors           :out    natural
    --TODO: Error log results 
  );
  
    --Internal test signals
    signal error_ctr           :       natural := 0;
    signal loop_ctr            :       natural := 0;
    signal exit_imm            :       boolean := false;
    signal rand_ctr            :       natural range 0 to 3800 := 0;

end entity;


Library ieee;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.ALL;
USE ieee.math_real.ALL;
USE work.randomLib.All;
use work.CANconstants.all;
USE work.CANtestLib.All;
 
--------------------------------------------------------------------------------
-- Test enity for feature tests. Additional signals representing two memory
-- buses are present to connect two DUTs of feature tests!     
--------------------------------------------------------------------------------
entity CAN_feature_test is
    port (

        -- Input trigger, test starts running when true
        signal run              : in    boolean;

        -- Number of iterations that test should do
        signal iterations       : in    natural;

        -- Logging level, severity which should be shown
        signal log_level        : in    log_lvl_type;

        -- Test behaviour when error occurs: Quit, or Go on
        signal error_beh        : in    err_beh_type;

        -- Error tolerance, error counter should not
        -- exceed this value in order for the test to pass
        signal error_tol        : in    natural;

        -- Status of the test                       
        signal status           : out   test_status_type;

        -- Amount of errors which appeared in the test
        signal errors           : out   natural;

        -- Memory access buses
        signal mem_bus_1        : inout Avalon_mem_type;
        signal mem_bus_2        : inout Avalon_mem_type;

        -- Bus level injected value and whether it should be forced on bus
        signal bl_inject        : in    std_logic;
        signal bl_force         : in    boolean
    );
  
    -- Internal test signals
    signal error_ctr            :       natural :=  0;
    signal loop_ctr             :       natural :=  0;
    signal exit_imm             :       boolean :=  false;
    signal rand_ctr             :       natural range 0 to 3800 := 0;
 
end entity;
 

USE work.CANtestLib.All; 
  
--------------------------------------------------------------------------------
-- Test wrapper. When executable test is created it implements architecture of
-- this entity! Note that within one test wrapper architecture several tests
-- can be implemented!!
--------------------------------------------------------------------------------
entity CAN_test_wrapper is
    generic(
        constant iterations   :     natural       :=  1000;
        constant log_level    :     log_lvl_type  :=  warning_l;
        constant error_beh    :     err_beh_type  :=  go_on;
        constant error_tol    :     natural       :=  0
    );
    port(
        signal status         :out  test_status_type
    );
end entity;
