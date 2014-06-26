require 'socket'

# TODO
# 1. OHLC
# 2. Results parser

module IQ
	class HistoryClient
		attr_accessor :max_tick_number, :start_session, :end_session, :old_to_new, :ticks_per_send

		def initialize(options)
			@host = options[:host] || 'localhost'
			@port = options[:port] || 9100
			@name = options[:name] || 'DEMO'
			@max_tick_number = options[:max_tick_number] || 50000
			@start_session = options[:start_session] || '000000'
			@end_session = options[:end_session] || '235959'
			@old_to_new = options[:old_to_new] || 1 		
			@ticks_per_send = options[:ticks_per_send] || 500
			@request_id = 0
		end

		def open
			@socket = TCPSocket.open @host, @port
			@socket.puts "S,SET CLIENT NAME," + @name
		end

		def process_request(req_id)
			exception = nil			
			while line = @socket.gets
				next unless line =~ /^#{req_id}/
				line.sub!(/^#{req_id},/, "") 
				if line =~ /^E,/
					exception = 'No Data'
				elsif line =~ /!ENDMSG!,/
					break
				end
				yield line
			end
			if exception
				raise exception
			end
		end

		def format_request_id(type)
			type.to_s + @request_id.to_s.rjust(7, '0')
		end

		def get_tick_days(ticket, days, &block)
			@socket.printf "HTD,%s,%07d,%07d,%s,%s,%d,0%07d,%07d\r\n", 
				ticket, days, 
				@max_tick_number, @start_session, @end_session, @old_to_new, @request_id, @ticks_per_send
			
			process_request(format_request_id(0)) do |line|
				block.call line
			end
			@request_id = @request_id + 1
		end

		def get_tick_range(ticket, start, finish, &block)
			@socket.printf "HTT,%s,%s,%s,%07d,%s,%s,%d,0%07d,%07d\r\n", 
				ticket, start.strftime("%Y%m%d %H%M%S"), finish.strftime("%Y%m%d %H%M%S"), 
				@max_tick_number, @start_session, @end_session, @old_to_new, @request_id, @ticks_per_send

			process_request(format_request_id(0)) do |line|
				block.call line
			end
			@request_id = @request_id + 1
		end

		def get_daily_range(ticket, start, finish, &block)
			@socket.printf "HDT,%s,%s,%s,%07d,%d,2%07d,%07d\r\n", 
				ticket, start.strftime("%Y%m%d %H%M%S"), finish.strftime("%Y%m%d %H%M%S"), 
				@max_tick_number, @old_to_new, @request_id, @ticks_per_send

			process_request(format_request_id(2)) do |line|
				block.call line
			end
			@request_id = @request_id + 1
		end

		def get_ohlc_days(ticket, interval_in_seconds, days, &block)
			@socket.printf "HID,%s,%07d,%07d,%07d,%s,%s,%d,1%07d,%07d\r\n", 
				ticket, interval_in_seconds, days, 
				@max_tick_number, @start_session, @end_session, @old_to_new, @request_id, @ticks_per_send
			
			process_request(format_request_id(1)) do |line|
				block.call line
			end
			@request_id = @request_id + 1
		end

		def get_ohlc_range(ticket, interval_in_seconds, start, finish, &block)
			@socket.printf "HIT,%s,%07d,%s,%s,%07d,%s,%s,%d,1%07d,%07d\r\n", 
				ticket, interval_in_seconds, start.strftime("%Y%m%d %H%M%S"), finish.strftime("%Y%m%d %H%M%S"), 
				@max_tick_number, @start_session, @end_session, @old_to_new, @request_id, @ticks_per_send

			process_request(format_request_id(1)) do |line|
				block.call line
			end
			@request_id = @request_id + 1
		end

		def close
			@socket.close
		end
	end
end