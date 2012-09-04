require "tempfile"
require "lumberjack_server"
require "insist"
require "stud/try"

describe "lumberjack" do
  before :all do
    # TODO(sissel): Generate a self-signed SSL cert
    @file = Tempfile.new("lumberjack-test-file")
    @ssl_cert = Tempfile.new("lumberjack-test-file")
    @ssl_key = Tempfile.new("lumberjack-test-file")
    @ssl_csr = Tempfile.new("lumberjack-test-file")

    # Generate the ssl key
    system("openssl genrsa -out #{@ssl_key.path} 1024")
    system("openssl req -new -key #{@ssl_key.path} -batch -out #{@ssl_csr.path}")
    system("openssl x509 -req -days 365 -in #{@ssl_csr.path} -signkey #{@ssl_key.path} -out #{@ssl_cert.path}")

    @server = Lumberjack::Server.new(
      :ssl_certificate => @ssl_cert.path,
      :ssl_key => @ssl_key.path
    )
    @lumberjack_pid = fork do
      exec("build/bin/lumberjack --host localhost --port #{@server.port} " \
           "--ssl-ca-path #{@ssl_cert.path} #{@file.path}")
    end

    @event_queue = Queue.new
    @server_thread = Thread.new do
      @server.run do |event|
        @event_queue << event
      end
    end
  end # before all

  after :all do
    @file.close
    @ssl_cert.close
    @ssl_key.close
    @ssl_csr.close
    Process::kill("KILL", @lumberjack_pid)
    Process::wait(@lumberjack_pid)
  end

  it "should follow a file and emit lines as events" do
    sleep 1 # let lumberjack start up.
    count = rand(5000) + 5000
    count.times do |i|
      @file.puts("hello #{i}")
    end
    @file.flush
    system("wc -l #{@file.path}")
    @file.close

    Stud::try(10.times) do
      raise "have #{@event_queue.size}, want #{count}" if @event_queue.size < count
    end

    insist { @event_queue.size } == count
    host = Socket.gethostname
    count.times do |i|
      event = @event_queue.pop
      insist { event["line"] } == "hello #{i}"
      insist { event["file"] } == @file.path
      insist { event["host"] } == host
    end
  end
end