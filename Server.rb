require 'thread'
require "socket"

class Server
  def initialize(size, ip, port)
    @port = port
    @ip = ip
    @server = TCPServer.new(@ip, @port)
    @connections = Hash.new
    @rooms = Hash.new
    @clients = Hash.new
    @connections[:server] = @server
    @connections[:rooms] = @rooms
    @connections[:clients] = @clients

    @size = size
    @jobs = Queue.new

    # Threadpooled Multithreaded Server to handle Client requests 
    # Each thread store its’ index in a thread-local variable  
    @pool = Array.new(@size) do |i|
      Thread.new do
        Thread.current[:id] = i

	# Shutdown of threads
        catch(:exit) do
          loop do
            job, args = @jobs.pop
            job.call(*args)
          end
        end
      end
    end
  run
  end
  
  def run
    loop do
      schedule(@server.accept) do |client|
	client.puts "Please Login to Connect (HELO text):"
        message = client.gets
          if message[0..3] == "HELO"
            n = message.length
	    nick_name = message[5..n]
            @connections[:clients].each do |other_name, other_client|
              if nick_name == other_name || client == other_client
                client.puts "This username already exists!"
                client.close
              end
            end
            @connections[:clients][nick_name] = client
            client.puts"\n#{message}IP:#{@ip}\nPort:#{@port}\nStudentID:11374331\n"
	    listen_client(client)
	  else
	    client.puts "Input not recognised"
	    client.close
          end 
      end
    end
    server.close
    at_exit { p.shutdown }
  end

  def schedule(*args, &block)
    @jobs << [block, args]
  end

  def listen_client(client)
    loop do
      $i = 0
      $num = 4
      msg = ""
        while $i < $num do
	  line = client.gets
          msg << line.chop << " "
	  $i +=1
        end
        if msg[0..13] == "JOIN_CHATROOM:"
          join_string = msg.split(" ")
	  n = join_string[0].length
	  room_name = join_string[0][14..n]
        elsif msg == "KILL_SERVICE\n"
          client.puts("Service Killed")
          @server.close
        else
          client.puts("Aw you put your own message! I'm just going to say Hey! Bye..")
        end
    end
  end
  
  def shutdown
    @size.times do
      schedule { throw :exit }
    end
    @pool.map(&:join)
  end
end

port = 2632
ip = Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }.ip_address
Server.new(10, ip, port)
