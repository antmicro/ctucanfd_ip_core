################################################################################
## 
## CAN with Flexible Data-Rate IP Core 
## 
## Copyright (C) 2017 Ondrej Ille <ondrej.ille@gmail.com>
## 
## Project advisor: Jiri Novak <jnovak@fel.cvut.cz>
## Department of Measurement         (http://meas.fel.cvut.cz/)
## Faculty of Electrical Engineering (http://www.fel.cvut.cz)
## Czech Technical University        (http://www.cvut.cz/)
## 
## Permission is hereby granted, free of charge, to any person obtaining a copy 
## of this VHDL component and associated documentation files (the "Component"), 
## to deal in the Component without restriction, including without limitation 
## the rights to use, copy, modify, merge, publish, distribute, sublicense, 
## and/or sell copies of the Component, and to permit persons to whom the 
## Component is furnished to do so, subject to the following conditions:
## 
## The above copyright notice and this permission notice shall be included in 
## all copies or substantial portions of the Component.
## 
## THE COMPONENT IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
## IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
## FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
## AUTHORS OR COPYRIGHTHOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
## LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
## FROM, OUT OF OR IN CONNECTION WITH THE COMPONENT OR THE USE OR OTHER DEALINGS 
## IN THE COMPONENT.
## 
## The CAN protocol is developed by Robert Bosch GmbH and protected by patents. 
## Anybody who wants to implement this IP core on silicon has to obtain a CAN 
## protocol license from Bosch.
## 
################################################################################

################################################################################
## Description:
## 			RX Buffers unit test handling script
################################################################################
global TCOMP

start_CAN_simulation "rx_buf_unit_test_wrapper"

################################################################################
# Adding the waves
################################################################################

#Add common waves for each test entity
add_test_status_waves
add_system_waves

#Add circuit specific signals
add wave -noupdate -divider -height 20 "DUT inputs (generated)"

add wave -group "Input metadata" \
	 -label "Frame Format" $TCOMP/rec_frame_type \
	 -label "Identifier type" $TCOMP/rec_ident_type \
	 -label "DLC" $TCOMP/rec_dlc \
	 -label "RTR" $TCOMP/rec_is_rtr \
	 -label "BRS" $TCOMP/rec_brs \
	 -label "ESI" $TCOMP/rec_esi

add wave -label "Identifier" $TCOMP/rec_ident

add wave -group "Commands from CAN Core" \
	 -label "Store metadata" $TCOMP/store_metadata_f \
	 -label "Store data" $TCOMP/store_data_f \
	 -label "Store data word" -hexadecimal $TCOMP/store_data_word \
	 -label "Receive valid" $TCOMP/rec_valid_f \
	 -label "Receive abort" $TCOMP/rec_abort_f \
	 -label "SOF pulse" $TCOMP/sof_pulse

add wave -label "Timestamp" -unsigned $TCOMP/timestamp
add wave -label "Timestamp options" -unsigned $TCOMP/drv_rtsopt
add wave -label "Erase Rx buffer" $TCOMP/rx_buffer_inst/drv_erase_rx
add wave -label "Read start" $TCOMP/rx_buffer_inst/drv_read_start

add wave -noupdate -divider -height 20 "RX Buffer status signals"
add wave -label "Buffer full" $TCOMP/rx_full
add wave -label "Buffer empty" $TCOMP/rx_empty
add wave -label "Stored frames" -unsigned $TCOMP/rx_message_count
add wave -label "Free 32bit words" -unsigned $TCOMP/rx_mem_free
add wave -label "Read pointer" -unsigned $TCOMP/rx_read_pointer_pos
add wave -label "Write pointer" -unsigned $TCOMP/rx_write_pointer_pos
add wave -label "Output word" -hexadecimal $TCOMP/rx_read_buff
add wave -label "Data overrun" -hexadecimal $TCOMP/rx_data_overrun

add wave -noupdate -divider -height 20 "RX Buffer internal signals"
add wave -label "FSM current" -hexadecimal $TCOMP/rx_buffer_inst/rx_buffer_fsm_inst/curr_state
add wave -label "FSM next" -hexadecimal $TCOMP/rx_buffer_inst/rx_buffer_fsm_inst/next_state
add wave -label "Read frame counter" -hexadecimal $TCOMP/rx_buffer_inst/read_frame_counter
add wave -label "Increment Read" -hexadecimal $TCOMP/rx_buffer_inst/read_increment
add wave -label "Intent to write word" -hexadecimal $TCOMP/rx_buffer_inst/write_raw_intent
add wave -label "Word OK to write" -hexadecimal $TCOMP/rx_buffer_inst/write_raw_OK
add wave -label "Write extra timestamp" -hexadecimal $TCOMP/rx_buffer_inst/write_extra_ts
add wave -label "Is free word" -hexadecimal $TCOMP/rx_buffer_inst/is_free_word
add wave -label "Overrun condition" -hexadecimal $TCOMP/rx_buffer_inst/overrun_condition
add wave -label "Write pointer extra timestamp" -hexadecimal $TCOMP/rx_buffer_inst/write_pointer_extra_ts
add wave -label "Write pointer RAW" -hexadecimal $TCOMP/rx_buffer_inst/write_pointer_raw
add wave -label "Memory write pointer" -hexadecimal $TCOMP/rx_buffer_inst/memory_write_pointer
add wave -label "Captured timestamp" -hexadecimal $TCOMP/rx_buffer_inst/timestamp_capture
add wave -label "Commit RX Frame" -hexadecimal $TCOMP/rx_buffer_inst/commit_rx_frame
add wave -label "Data overrun internal" -hexadecimal $TCOMP/rx_buffer_inst/data_overrun_int


add wave -noupdate -divider -height 20 "Testbench internal signals"
add wave -label "Input memory full" $TCOMP/in_mem_full
add wave -label "Output memory full" $TCOMP/out_mem_full
add wave -label "Input memory" -hexadecimal $TCOMP/in_mem
add wave -label "Output memory" -hexadecimal $TCOMP/out_mem	
add wave -label "Input mem pointer" -unsigned $TCOMP/in_pointer
add wave -label "Output mem pointer" -unsigned $TCOMP/out_pointer	
add wave -label "???InMem=OutMem???" $TCOMP/cons_check/cons_res

add wave -noupdate -divider -height 20 "Internal DUT signals"
add wave -label "RX Buffer content" $TCOMP/rx_buffer_inst/rx_buf_RAM/ram_memory


								 
################################################################################
# Execute the simulation, gather results
################################################################################
run_simulation
get_test_results

