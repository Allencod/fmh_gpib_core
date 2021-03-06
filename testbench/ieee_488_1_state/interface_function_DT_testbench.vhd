-- testbench for ieee 488.1 device trigger interface function.
-- Author: Frank Mori Hess fmh6jj@gmail.com
-- Copyright 2017 Frank Mori Hess
--

library IEEE;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.interface_function_common.all;

entity interface_function_DT_testbench is
end interface_function_DT_testbench;
     
architecture behav of interface_function_DT_testbench is
	signal clock : std_logic;
	signal acceptor_handshake_state : AH_state;
	signal listener_state_p1 : LE_state_p1;
	signal GET : std_logic;
	signal device_trigger_state : DT_state;
	
	constant clock_half_period : time := 50 ns;

	shared variable test_finished : boolean := false;

	begin
	my_DT: entity work.interface_function_DT 
		port map (
			acceptor_handshake_state => acceptor_handshake_state,
			listener_state_p1 => listener_state_p1,
			GET => GET,
			device_trigger_state => device_trigger_state
		);
	
	process
	begin
		if(test_finished) then
			wait;
		end if;
		
		clock <= '0';
		wait for clock_half_period;
		clock <= '1';
		wait for clock_half_period;
	end process;
	
	process
		-- wait wait for a condition with a hard coded timeout to avoid infinite test loops on failure
		procedure wait_for_ticks (num_clock_cycles : in integer) is
			begin
				for i in 1 to num_clock_cycles loop
					wait until rising_edge(clock);
				end loop;
			end procedure wait_for_ticks;
		
	begin
		acceptor_handshake_state <= AIDS;
		listener_state_p1 <= LIDS;
		GET <= '0';
				
		wait until rising_edge(clock);
		
		assert device_trigger_state = DTIS;

		GET <= '1';
		listener_state_p1 <= LADS;
		acceptor_handshake_state <= ACDS;
		wait_for_ticks(3);
		assert device_trigger_state <= DTAS;
		
		GET <= '0';
		wait_for_ticks(3);
		assert device_trigger_state <= DTIS;

		wait until rising_edge(clock);
		assert false report "end of test" severity note;
		test_finished := true;
		wait;
	end process;
end behav;
