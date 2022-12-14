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
--  Definition of context for synthesizable codes of CTU CAN FD.
--
--  Context definitions are used for tests only since free version of Quartus
--  does not support context clause for synthesis.
--------------------------------------------------------------------------------
-- Revision History:
--   28.12.2018   Created file - Ondrej Ille
--------------------------------------------------------------------------------

context ctu_can_synth_context is

    Library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.ALL;
    use ieee.math_real.ALL;
    
    Library ctu_can_fd_rtl;
    use ctu_can_fd_rtl.id_transfer.all;
    use ctu_can_fd_rtl.can_constants.all;
    use ctu_can_fd_rtl.can_components.all;
    use ctu_can_fd_rtl.can_types.all;
    use ctu_can_fd_rtl.cmn_lib.all;
    use ctu_can_fd_rtl.drv_stat_pkg.all;
    use ctu_can_fd_rtl.reduce_lib.all;
    use ctu_can_fd_rtl.can_config.all;
    
    use ctu_can_fd_rtl.CAN_FD_register_map.all;
    use ctu_can_fd_rtl.CAN_FD_frame_format.all;
end context;
