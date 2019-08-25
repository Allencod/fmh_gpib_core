-- IEEE 488.1 extended source handshake (SHE) interface function
--
-- If you just want the simpler SH function, you can leave the "nie", 
-- "CNCS", "T11_terminal_count", "T12_terminal_count", "T13_terminal_count", 
-- "T14_terminal_count", and "T16_terminal_count" inputs unconnected, also
-- it won't matter what you connect to the IFC input.
--
-- Author: Frank Mori Hess fmh6jj@gmail.com
-- Copyright Frank Mori Hess 2017, 2019


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.interface_function_common.all;

entity interface_function_SHE is
	generic( num_counter_bits : in integer := 8);
	port(
		clock : in std_logic;
		talker_state_p1 : in TE_state_p1;
		controller_state_p1 : in C_state_p1;
		CNCS : in std_logic := '1'; -- from CF interface function
		ATN : in std_logic;
		DAC : in std_logic;
		IFC : in std_logic;
		RFD : in std_logic;
		nba : in std_logic;
		nie : in std_logic := '0';
		pon : in std_logic;
		first_T1_terminal_count : in unsigned (num_counter_bits - 1 downto 0); -- longer T1 used for first cycle only
		T1_terminal_count : in unsigned (num_counter_bits - 1 downto 0);
		T11_terminal_count : in unsigned (num_counter_bits - 1 downto 0) := (others => '1');
		T12_terminal_count : in unsigned (num_counter_bits - 1 downto 0) := (others => '1');
		T13_terminal_count : in unsigned (num_counter_bits - 1 downto 0) := (others => '1');
		T14_terminal_count : in unsigned (num_counter_bits - 1 downto 0) := (others => '1');
		T16_terminal_count : in unsigned (num_counter_bits - 1 downto 0) := (others => '1');
		check_for_listeners : in std_logic; -- do optional check in SDYS for listeners

		source_handshake_state : out SH_state;
		noninterlocked_enable_state : out SH_noninterlocked_state;
		DAV : out std_logic;
		NIC : out std_logic;
		no_listeners : out std_logic -- pulses true during SDYS if no listeners are detected at end of T1 delay
	);
 
end interface_function_SHE;
 
architecture interface_function_SHE_arch of interface_function_SHE is
 
	signal interrupt : boolean;
	signal active : boolean;
	signal ready_for_noninterlocked : boolean;
	signal current_count : unsigned(num_counter_bits - 1 downto 0);
	signal first_cycle : boolean; -- we are on the first transfer since leaving SIDS
	-- used to insure we only report no listeners one time during SDYS
	signal no_listeners_reported : boolean;
	signal source_handshake_state_buffer : SH_state; -- buffer works around inability to read outputs
	signal noninterlocked_enable_state_buffer : SH_noninterlocked_state; -- buffer works around inability to read outputs
 
begin
 
	interrupt <= (to_bit(ATN) = '1' and controller_state_p1 /= CACS and controller_state_p1 /= CTRS) or
		 (to_bit(ATN) = '0' and talker_state_p1 /= TACS and talker_state_p1 /= SPAS);
	active <= talker_state_p1 = TACS or talker_state_p1 = SPAS or controller_state_p1 = CACS;	
	source_handshake_state <= source_handshake_state_buffer;
	noninterlocked_enable_state <= noninterlocked_enable_state_buffer;
	ready_for_noninterlocked <= to_X01(nie) = '1' and to_X01(CNCS) = '0';
	
	process(pon, clock) 
		variable T1_counter_done : boolean;
		variable T13_counter_done : boolean;
		variable TN_counter_done : boolean;
	begin
		if pon = '1' then
			source_handshake_state_buffer <= SIDS;
			noninterlocked_enable_state_buffer <= SNDS;
			no_listeners <= '0';
			current_count <= to_unsigned(0, num_counter_bits);
			T1_counter_done := false;
			T13_counter_done := false;
			TN_counter_done := false;
			first_cycle <= false;
			no_listeners_reported <= false;
		elsif rising_edge(clock) then
			-- no_listeners only pulses high for 1 clock so clear it.  no_listeners may
			-- be set high (for a cycle) later in this process.
			no_listeners <= '0';
			
			case source_handshake_state_buffer is
				when SIDS =>
					if (talker_state_p1 = TACS and not ready_for_noninterlocked) or 
						talker_state_p1 = SPAS or controller_state_p1 = CACS then
						source_handshake_state_buffer <= SGNS;
					elsif (talker_state_p1 = TACS and ready_for_noninterlocked) then
						source_handshake_state_buffer <= SWRS;
						current_count <= to_unsigned(0, current_count'length);
					end if;
					first_cycle <= true;
				when SGNS =>
					if nba = '1' then
						current_count <= to_unsigned(0, current_count'length);
						no_listeners_reported <= false;
						source_handshake_state_buffer <= SDYS;
					elsif interrupt then
						source_handshake_state_buffer <= SIDS;
					end if;
				when SDYS =>
					-- check if T1 delay is done
					T1_counter_done := (first_cycle and current_count >= 
						first_T1_terminal_count) or
						(first_cycle = false and current_count >= T1_terminal_count);
					-- check if T13 delay is done
					T13_counter_done := (current_count >= T13_terminal_count);
					
					if not T1_counter_done or not T13_counter_done then
						current_count <= current_count + 1;
					end if;
					
					-- transitions
					if interrupt then
						source_handshake_state_buffer <= SIDS;
					elsif to_X01(RFD) = '1' then
						if (T13_counter_done and to_X01(DAC) = '1' and noninterlocked_enable_state_buffer = SNES) then
							source_handshake_state_buffer <= STRS;
							current_count <= to_unsigned(0, current_count'length);
						elsif T1_counter_done then
							if(check_for_listeners = '0' or to_X01(DAC) = '0') then
								first_cycle <= false;
								source_handshake_state_buffer <= STRS;
								current_count <= to_unsigned(0, current_count'length);
							elsif (no_listeners_reported = false and noninterlocked_enable_state_buffer /= SNES) then
								no_listeners <= '1';
								no_listeners_reported <= true;
							end if;
						end if;
					end if;
				when STRS =>
					-- check if T14 delay is done
					TN_counter_done := (current_count >= T14_terminal_count);

					if not TN_counter_done then
						current_count <= current_count + 1;
					end if;
					
					if interrupt then
						source_handshake_state_buffer <= SIWS;
					elsif to_X01(DAC) = '1' and 
						(
							to_X01(CNCS) = '1' or talker_state_p1 /= TACS or 
							(noninterlocked_enable_state_buffer = SNDS and to_X01(RFD) = '0') or 
							(noninterlocked_enable_state_buffer = SNES and TN_counter_done)
						) then
						source_handshake_state_buffer <= SWNS;
					end if;
				when SWNS =>
					if to_bit(nba) = '0' then
						source_handshake_state_buffer <= SGNS;
					elsif interrupt then
						source_handshake_state_buffer <= SIWS;
					end if;
				when SIWS =>
					if to_bit(nba) = '0' then
						source_handshake_state_buffer <= SIDS;
					elsif active then
						source_handshake_state_buffer <= SWNS;
					end if;
					first_cycle <= true;
				when SWRS =>
					-- check if T16 delay is done
					TN_counter_done := (current_count >= T16_terminal_count);
					if not TN_counter_done then
						current_count <= current_count + 1;
					end if;

					if interrupt then
						source_handshake_state_buffer <= SIDS;
					elsif TN_counter_done and to_X01(RFD) = '1' then
						source_handshake_state_buffer <= SRDS;
						current_count <= to_unsigned(0, current_count'length);
					end if;
				when SRDS =>
					-- check if T11 delay is done
					TN_counter_done := (current_count >= T11_terminal_count);
					if not TN_counter_done then
						current_count <= current_count + 1;
					end if;

					if interrupt then
						source_handshake_state_buffer <= SIDS;
					elsif TN_counter_done and to_X01(RFD) = '1' then
						source_handshake_state_buffer <= SNGS;
						current_count <= to_unsigned(0, current_count'length);
						TN_counter_done := false;
					end if;
				when SNGS =>
					-- check if T12 delay is done
					TN_counter_done := (current_count >= T12_terminal_count);
					if not TN_counter_done then
						current_count <= current_count + 1;
					end if;

					if interrupt then
						source_handshake_state_buffer <= SIDS;
					elsif TN_counter_done and to_X01(RFD) = '1' then
						source_handshake_state_buffer <= SGNS;
					end if;
			end case;
			
			case noninterlocked_enable_state_buffer is
				when SNDS =>
					if source_handshake_state_buffer = STRS and to_X01(RFD) = '1' and 
						to_X01(DAC) = '1' 
					then
						noninterlocked_enable_state_buffer <= SNES;
					end if;
				when SNES =>
					if to_X01(ATN) = '1' or to_X01(RFD) = '0' then
						noninterlocked_enable_state_buffer <= SNDS;
					end if;
			end case;

			if to_X01(IFC) = '1' then
				noninterlocked_enable_state_buffer <= SNDS;
			end if;
		end if;
	end process;

	-- set local message outputs as soon as state changes for low latency
	process(source_handshake_state_buffer) begin
		case source_handshake_state_buffer is
			when SIDS =>
				DAV <= 'L';
				NIC <= 'L';
			when SGNS =>
				DAV <= '0';
				NIC <= 'L';
			when SDYS =>
				DAV <= '0';
				NIC <= 'L';
			when STRS =>
				DAV <= '1';
				NIC <= 'L';
			when SWNS =>
				DAV <= '0';
				NIC <= 'L';
			when SIWS =>
				DAV <= 'L';
				NIC <= 'L';
			when SWRS =>
				DAV <= '0';
				NIC <= 'L';
			when SRDS =>
				DAV <= '0';
				NIC <= 'L';
			when SNGS =>
				DAV <= '0';
				NIC <= '1';
		end case;
	end process;
	
end interface_function_SHE_arch;
