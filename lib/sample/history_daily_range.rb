require '../iqfeed'

o = Iqfeed::HistoryObserver.new
c = Iqfeed::HistoryClient.new
c.open
# 2 hours of tick history
c.get_daily_range({:symbol => '@EU#', :from => Time.now - 3600*24, :to => Time.now}, o)
c.run
