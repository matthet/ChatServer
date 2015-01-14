require 'thread'
require "socket"

class Server
  def initialize(size, ip, port)
    @port = port
    @ip = ip
    @server = TCPServer.new(@ip, @port)
    @rooms = Hash.new
    @clients = Hash.new
    @room_names = Hash.new
    @room_refs = Hash.new
    @client_ips = Hash.new
    @join_ids = Hash.new
    @rooms[:room_names] = @room_names
    @rooms[:room_refs] = @room_refs
    @clients[:client_ips] = @client_ips
    @clients[:join_ids] = @join_ids

    @room_ref = 0
    @join_id = 0

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
  
  # Tell the pool that work is to be done: a client is trying to connect
  def schedule(*args, &block)
    @jobs << [block, args]
  end

  # Entry Point
  # Schedule a client request
  def run
    loop do
      schedule(@server.accept) do |client|
        listen_client(client)
      end
    end
    server.close
    at_exit { p.shutdown }
  end
    
  # Listen and Respond to all Client instance messages
  def listen_client(client)
    loop do
      request = client.gets
      puts request
      if request[0..3] == "HELO"
        nick_name = request[5..request.length].chop
        client.puts "HELO #{nick_name}\nIP:#{@ip}\nPort:#{@port}\nStudentID:11374331"
      elsif request[0..13] == "JOIN_CHATROOM:"
        room_name = request[14..request.length-1].chop
        i = 0
        while i < 3
          line = client.gets.chop
          i += 1
        end
        nick_name = line[12..line.length-1]
        join_request(room_name, nick_name, client)
      elsif request[0..14] == "LEAVE_CHATROOM:"
        room_ref = request[16..request.length-1].chop
        line = client.gets.chop
        join_id = line[9..line.length-1]
        line = client.gets.chop
        nick_name = line[13..line.length-1]
        leave_request(room_ref, join_id, nick_name, client)
      elsif request[0..4] == "CHAT:"
        $i = 0
        request.chop << " "
        while $i < 2 do
          line = client.gets
          request << line.chop << " "
          $i += 1
        end
        chat_s = request.split(" ")
        room_ref = chat_s[0][5..chat_s[0].length-1]
        join_id = chat_s[1][8..chat_s[1].length-1]
        nick_name = chat_s[2][12..chat_s[2].length-1]
        message = client.gets.chop
        chat_request(room_ref, nick_name, message, client)
      elsif request[0..11] == "DISCONNECT:0"
        client.close
      elsif msg == "KILL_SERVICE"
        client.puts("Service Killed")
        @server.close
      end
    end
  end

  # Add client to chat room specified
  # Create the chat room if it doesn't already exist
  def join_request(room_name, nick_name, client)
    @clients[:client_ips].each do |other_name, other_client|
      if nick_name == other_name || client == other_client
        client.puts "This username already exists!"
        client.close
      end
    end
    @clients[:client_ips][nick_name] = client
    room_exists = 0
    local_room_ref = 0
    @rooms[:room_names].each do |other_name, room_ref|
      if room_name == other_name
        local_room_ref = @rooms[:room_names][room_name]
        room_exists = 1
      end
    end
    if room_exists == 0
      @room_ref += 1
      local_room_ref = @room_ref
      @rooms[:room_names][room_name] = local_room_ref
    end
    (@rooms[:room_refs][local_room_ref] ||= []) << nick_name
    @join_id += 1
    @clients[:join_ids][nick_name] = @join_id
    client.puts "JOINED_CHATROOM:#{room_name}\nSERVER_IP:#{@ip}\nPORT:#{@port}\nROOM_REF:#{local_room_ref}\nJOIN_ID:#{@join_id}"
    @rooms[:room_refs][local_room_ref].each do |other_member_name|
      @clients[:client_ips].each do |other_name, other_client|
        if other_member_name == other_name
          other_client.puts "CHAT:#{local_room_ref}\nCLIENT_NAME:#{nick_name}\nMESSAGE:#{nick_name} has joined this chatroom."
        end
      end
    end
  end

  # Remove client from chat room specified
  # Error if room_ref does not exist or client is not a member
  def leave_request(room_ref, join_id, nick_name, client)
    local_room_ref = 0
    $error_string = "\nERROR_CODE:0\nERROR_DESCRIPTION:Given Room Ref does not exist\n\n"
      @rooms[:room_names].each do |other_room_name, other_ref|
       if room_ref == other_ref.to_s
         local_room_ref = @rooms[:room_names][other_room_name]
       end
      end
    if local_room_ref == 0
      client.puts $error_string
    else
      first_leave = 0
      @rooms[:room_refs][local_room_ref].each do |other_name|
        if nick_name == other_name
	  first_leave = 1
	  @rooms[:room_refs][local_room_ref].delete nick_name
        end
      end
      if first_leave == 1
	#tell chatroom
      end
      client.puts "\nLEFT_CHATROOM:#{local_room_ref}\nJOIN_ID:#{join_id}\n\n"
    end
  end

  # Send message to other members of chatroom
  def chat_request(room_ref, nick_name, message, client)
    ref = room_ref.to_i
    @rooms[:room_refs][ref].each do |other_member_name|
      unless other_member_name == nick_name
        @clients[:client_ips].each do |other_name, other_client|
          if other_member_name == other_name
            other_client.puts "\nCHAT:#{room_ref}\nCLIENT_NAME:#{nick_name}\nMESSAGE:#{message}\n\n"
          end
        end
      end
    end
  end	  

  # When closing down application, wait for any jobs in the pool to finish before exit 
  def shutdown
    @size.times do
      schedule { throw :exit }
    end
    @pool.map(&:join)
  end
end

# Initialise the Server
port = 2632
ip = Socket.ip_address_list.find { |ai| ai.ipv4? && !ai.ipv4_loopback? }.ip_address
Server.new(10, ip, port)
