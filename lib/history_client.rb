require 'socket'

module IQ
	class Tick
		attr_accessor :time_stamp, :last_price, :last_size, :total_volume, :bid, :ask, :tick_id
		
		def self.parse(line)
			tick = Tick.new
			fields = line.split(',')
			tick.time_stamp = fields[0]
			tick.last_price = fields[1]
			tick.last_size = fields[2]
			tick.total_volume = fields[3]
			tick.bid = fields[4]
			tick.ask = fields[5]
			tick			
		end 

		def to_s
			"Timestamp:#{@time_stamp} LastPrice:#{@last_price} LastSize:#{@last_size} TotalVolume:#{@total_volume} Bid:#{@bid} Ask:#{@ask}"
		end

		def to_csv
			[@time_stamp, @last_price, @last_size, @total_volume, @bid, @ask].join(';')
		end
	end

	class OHLC
		attr_accessor :time_stamp, :high, :low, :open, :close, :total_volume, :period_volume
		
		def self.parse(line)
			ohlc = OHLC.new
			fields = line.split(',')
			ohlc.time_stamp = fields[0]
			ohlc.high = fields[1]
			ohlc.low = fields[2]
			ohlc.open = fields[3]
			ohlc.close = fields[4]
			ohlc.total_volume = fields[5]
			ohlc.period_volume = fields[6]
			ohlc			
		end 

		def to_s
			"Timestamp:#{@time_stamp} High:#{@high} Low:#{@low} Open:#{@open} Close:#{@close} TotalVolume:#{@total_volume} PeriodVolume:#{@period_volume}"
		end

		def to_csv
			[@time_stamp, @high, @low, @open, @close, @total_volume, @period_volume].join(';')
		end
	end

	class DWM # day, week, month
		attr_accessor :time_stamp, :high, :low, :open, :close, :period_volume, :open_interest
		
		def self.parse(line)
			dwm = DWM.new
			fields = line.split(',')
			dwm.time_stamp = fields[0]
			dwm.high = fields[1]
			dwm.low = fields[2]
			dwm.open = fields[3]
			dwm.close = fields[4]
			dwm.period_volume = fields[5]
			dwm.open_interest = fields[6]
			dwm			
		end 

		def to_s
			"Timestamp:#{@time_stamp} High:#{@high} Low:#{@low} Open:#{@open} Close:#{@close} PeriodVolume:#{@period_volume} OpenInterest:#{@open_interest}"
		end

		def to_csv
			[@time_stamp, @high, @low, @open, @close, @period_volume, @open_interest].join(';')
		end
	end

	class HistoryClient
		attr_accessor :max_tick_number, :start_session, :end_session, :old_to_new, :ticks_per_send

		def initialize(options = {})
			parse_options(options)
			@request_id = 0
		end

		def parse_options(options)
			@host = options[:host] || 'localhost'
			@port = options[:port] || 9100
			@name = options[:name] || 'DEMO'
			@max_tick_number = options[:max_tick_number] || 50000
			@start_session = options[:start_session] || '000000'
			@end_session = options[:end_session] || '235959'
			@old_to_new = options[:old_to_new] || 1 		
			@ticks_per_send = options[:ticks_per_send] || 500
		end

		def open
			@socket = TCPSocket.open @host, @port
			@socket.puts "S,SET CLIENT NAME," + @name
		end

		def process_request(req_id)
			exception = nil
			case req_id[0]
				when '0'					
					parse = Proc.new{|line| IQ::Tick.parse(line)}
				when '1'
					parse = Proc.new{|line| IQ::OHLC.parse(line)}
				when '2'
					parse = Proc.new{|line| IQ::DWM.parse(line)}
				end		
			while line = @socket.gets
				next unless line =~ /^#{req_id}/
				line.sub!(/^#{req_id},/, "") 
				if line =~ /^E,/
					exception = 'No Data'
				elsif line =~ /!ENDMSG!,/
					break
				end
				yield parse.call(line)
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