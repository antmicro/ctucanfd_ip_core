--------------------------------------------------------------------------------
-- 
-- CAN with Flexible Data-Rate IP Core 
-- 
-- Copyright (C) 2017 Ondrej Ille <ondrej.ille@gmail.com>
-- 
-- Project advisor: Jiri Novak <jnovak@fel.cvut.cz>
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
-- Addresses map for: CAN_FD_frame_format
-- Field map for: CAN_FD_frame_format
-- This file is autogenerated, DO NOT EDIT!
--------------------------------------------------------------------------------

Library ieee;
use ieee.std_logic_1164.all;

package CAN_FD_frame_format is

  ------------------------------------------------------------------------------
  ------------------------------------------------------------------------------
  -- Address block: CAN_FD_Frame_format
  ------------------------------------------------------------------------------
  ------------------------------------------------------------------------------
  constant CAN_FD_FRAME_FORMAT_BLOCK    : std_logic_vector(3 downto 0) := x"0";

  constant FRAME_FORM_W_ADR          : std_logic_vector(11 downto 0) := x"000";
  constant IDENTIFIER_W_ADR          : std_logic_vector(11 downto 0) := x"004";
  constant TIMESTAMP_L_W_ADR         : std_logic_vector(11 downto 0) := x"008";
  constant TIMESTAMP_U_W_ADR         : std_logic_vector(11 downto 0) := x"00C";
  constant DATA_1_4_W_ADR            : std_logic_vector(11 downto 0) := x"010";
  constant DATA_5_8_W_ADR            : std_logic_vector(11 downto 0) := x"014";
  constant DATA_9_12_W_ADR           : std_logic_vector(11 downto 0) := x"018";
  constant DATA_13_16_W_ADR          : std_logic_vector(11 downto 0) := x"01C";
  constant DATA_17_20_W_ADR          : std_logic_vector(11 downto 0) := x"020";
  constant DATA_21_24_W_ADR          : std_logic_vector(11 downto 0) := x"024";
  constant DATA_25_28_W_ADR          : std_logic_vector(11 downto 0) := x"028";
  constant DATA_29_32_W_ADR          : std_logic_vector(11 downto 0) := x"02C";
  constant DATA_33_36_W_ADR          : std_logic_vector(11 downto 0) := x"030";
  constant DATA_37_40_W_ADR          : std_logic_vector(11 downto 0) := x"034";
  constant DATA_41_44_W_ADR          : std_logic_vector(11 downto 0) := x"038";
  constant DATA_45_48_W_ADR          : std_logic_vector(11 downto 0) := x"03C";
  constant DATA_49_52_W_ADR          : std_logic_vector(11 downto 0) := x"040";
  constant DATA_53_56_W_ADR          : std_logic_vector(11 downto 0) := x"044";
  constant DATA_57_60_W_ADR          : std_logic_vector(11 downto 0) := x"048";
  constant DATA_61_64_W_ADR          : std_logic_vector(11 downto 0) := x"04C";

  ------------------------------------------------------------------------------
  -- FRAME_FORM_W register
  --
  -- Frame format word with basic frame information.
  ------------------------------------------------------------------------------
  constant DLC_L                  : natural := 0;
  constant DLC_H                  : natural := 3;
  constant RTR_IND                : natural := 5;
  constant ID_TYPE_IND            : natural := 6;
  constant FR_TYPE_IND            : natural := 7;
  constant TBF_IND                : natural := 8;
  constant BRS_IND                : natural := 9;
  constant ESI_RESVD_IND         : natural := 10;

  -- "RTR" field enumerated values
  constant NO_RTR_FRAME       : std_logic := '0';
  constant RTR_FRAME          : std_logic := '1';

  -- "ID_TYPE" field enumerated values
  constant BASE               : std_logic := '0';
  constant EXTENDED           : std_logic := '1';

  -- "FR_TYPE" field enumerated values
  constant NORMAL_CAN         : std_logic := '0';
  constant FD_CAN             : std_logic := '1';

  -- "TBF" field enumerated values
  constant NOT_TIME_BASED     : std_logic := '0';
  constant TIME_BASED         : std_logic := '1';

  -- "BRS" field enumerated values
  constant BR_NO_SHIFT        : std_logic := '0';
  constant BR_SHIFT           : std_logic := '1';

  -- "ESI_RESVD" field enumerated values
  constant ESI_ERR_ACTIVE     : std_logic := '0';
  constant ESI_ERR_PASIVE     : std_logic := '1';

  -- FRAME_FORM_W register reset values

  ------------------------------------------------------------------------------
  -- IDENTIFIER_W register
  --
  -- CAN Identifier
  ------------------------------------------------------------------------------
  constant IDENTIFIER_BASE_L      : natural := 0;
  constant IDENTIFIER_BASE_H     : natural := 10;
  constant IDENTIFIER_EXT_L      : natural := 11;
  constant IDENTIFIER_EXT_H      : natural := 28;

  -- IDENTIFIER_W register reset values

  ------------------------------------------------------------------------------
  -- TIMESTAMP_L_W register
  --
  -- Lower 32 bits of timestamp when the frame should be transmitted or when it 
  -- was received.
  ------------------------------------------------------------------------------
  constant TIME_STAMP_31_0_L      : natural := 0;
  constant TIME_STAMP_31_0_H     : natural := 31;

  -- TIMESTAMP_L_W register reset values

  ------------------------------------------------------------------------------
  -- TIMESTAMP_U_W register
  --
  -- Upper 32 bits of timestamp when the frame should be transmitted or when it 
  -- was received.
  ------------------------------------------------------------------------------
  constant TIMESTAMP_L_W_L        : natural := 0;
  constant TIMESTAMP_L_W_H       : natural := 31;

  -- TIMESTAMP_U_W register reset values

  ------------------------------------------------------------------------------
  -- DATA_1_4_W register
  --
  ------------------------------------------------------------------------------
  constant DATA_1_TO_DATA_4_L     : natural := 0;
  constant DATA_1_TO_DATA_4_H    : natural := 31;

  -- DATA_1_4_W register reset values

  ------------------------------------------------------------------------------
  -- DATA_5_8_W register
  --
  ------------------------------------------------------------------------------
  constant DATA_5_TO_DATA_8_L     : natural := 0;
  constant DATA_5_TO_DATA_8_H    : natural := 31;

  -- DATA_5_8_W register reset values

  ------------------------------------------------------------------------------
  -- DATA_9_12_W register
  --
  ------------------------------------------------------------------------------
  constant DATA_9_TO_DATA_12_L    : natural := 0;
  constant DATA_9_TO_DATA_12_H   : natural := 31;

  -- DATA_9_12_W register reset values

  ------------------------------------------------------------------------------
  -- DATA_13_16_W register
  --
  ------------------------------------------------------------------------------
  constant DATA_13_TO_DATA_16_L   : natural := 0;
  constant DATA_13_TO_DATA_16_H  : natural := 31;

  -- DATA_13_16_W register reset values

  ------------------------------------------------------------------------------
  -- DATA_17_20_W register
  --
  ------------------------------------------------------------------------------
  constant DATA_17_TO_DATA_20_L   : natural := 0;
  constant DATA_17_TO_DATA_20_H  : natural := 31;

  -- DATA_17_20_W register reset values

  ------------------------------------------------------------------------------
  -- DATA_21_24_W register
  --
  ------------------------------------------------------------------------------
  constant DATA_21_TO_DATA_24_L   : natural := 0;
  constant DATA_21_TO_DATA_24_H  : natural := 31;

  -- DATA_21_24_W register reset values

  ------------------------------------------------------------------------------
  -- DATA_25_28_W register
  --
  ------------------------------------------------------------------------------
  constant DATA_25_TO_DATA_28_L   : natural := 0;
  constant DATA_25_TO_DATA_28_H  : natural := 31;

  -- DATA_25_28_W register reset values

  ------------------------------------------------------------------------------
  -- DATA_29_32_W register
  --
  ------------------------------------------------------------------------------
  constant DATA_29_TO_DATA_32_L   : natural := 0;
  constant DATA_29_TO_DATA_32_H  : natural := 31;

  -- DATA_29_32_W register reset values

  ------------------------------------------------------------------------------
  -- DATA_33_36_W register
  --
  ------------------------------------------------------------------------------
  constant DATA_33_TO_DATA_36_L   : natural := 0;
  constant DATA_33_TO_DATA_36_H  : natural := 31;

  -- DATA_33_36_W register reset values

  ------------------------------------------------------------------------------
  -- DATA_37_40_W register
  --
  ------------------------------------------------------------------------------
  constant DATA_37_TO_DATA_40_L   : natural := 0;
  constant DATA_37_TO_DATA_40_H  : natural := 31;

  -- DATA_37_40_W register reset values

  ------------------------------------------------------------------------------
  -- DATA_41_44_W register
  --
  ------------------------------------------------------------------------------
  constant DATA_41_TO_DATA_44_L   : natural := 0;
  constant DATA_41_TO_DATA_44_H  : natural := 31;

  -- DATA_41_44_W register reset values

  ------------------------------------------------------------------------------
  -- DATA_45_48_W register
  --
  ------------------------------------------------------------------------------
  constant DATA_45_TO_DATA_48_L   : natural := 0;
  constant DATA_45_TO_DATA_48_H  : natural := 31;

  -- DATA_45_48_W register reset values

  ------------------------------------------------------------------------------
  -- DATA_49_52_W register
  --
  ------------------------------------------------------------------------------
  constant DATA_49_TO_DATA_52_L   : natural := 0;
  constant DATA_49_TO_DATA_52_H  : natural := 31;

  -- DATA_49_52_W register reset values

  ------------------------------------------------------------------------------
  -- DATA_53_56_W register
  --
  ------------------------------------------------------------------------------
  constant DATA_53_TO_DATA_56_L   : natural := 0;
  constant DATA_53_TO_DATA_56_H  : natural := 31;

  -- DATA_53_56_W register reset values

  ------------------------------------------------------------------------------
  -- DATA_57_60_W register
  --
  ------------------------------------------------------------------------------
  constant DATA_57_TO_DATA_60_L   : natural := 0;
  constant DATA_57_TO_DATA_60_H  : natural := 31;

  -- DATA_57_60_W register reset values

  ------------------------------------------------------------------------------
  -- DATA_61_64_W register
  --
  ------------------------------------------------------------------------------
  constant DATA_61_TO_DATA_64_L   : natural := 0;
  constant DATA_61_TO_DATA_64_H  : natural := 31;

  -- DATA_61_64_W register reset values

end package;
