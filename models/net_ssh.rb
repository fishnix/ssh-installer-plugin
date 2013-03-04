require 'net/sftp'

class Net::SFTP::Session
  def exists?(path, flags=nil, &callback)
    begin
      wait_for(stat(path, flags, &callback), :attrs)
    rescue Net::SFTP::StatusException => e 
      raise unless e.code == 2
      false
    end
  end
end