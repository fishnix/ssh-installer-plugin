require 'rubygems'
require 'net/ssh'
require 'net/sftp'

class Ssh_installerBuilder < Jenkins::Tasks::Builder

  display_name "Do Stuff over SSH"

  attr_accessor :node_name
  attr_accessor :conn_string
  attr_accessor :host
  attr_accessor :port
  attr_accessor :user
  attr_accessor :ssh_key
  attr_accessor :ssh_pass
  attr_accessor :ssh_env
  attr_accessor :ssh_cmds
  attr_accessor :stage_dir
  
  
  # Invoked with the form parameters when this extension point
  # is created from a configuration screen.
  def initialize(attrs = {})
    @node_name = attrs['node_name']
    @conn_string = attrs['conn_string']
    
    conn_attr = parse_conn_string attrs['conn_string']
    @host = conn_attr[:host]
    @port = conn_attr[:port] ||= 22
    @user = conn_attr[:user]
    
    @ssh_key =  attrs['ssh_key']    == "" ? nil : attrs['ssh_key']
    @ssh_pass = attrs['ssh_pass']   == "" ? nil : attrs['ssh_pass']
    
    @ssh_env =  attrs['ssh_env']
    @ssh_cmds = attrs['ssh_cmds']
    
    @stage_dir = attrs['stage_dir'] == "" ? './' : attrs['stage_dir']
  end

  ##
  # Runs before the build begins
  #
  # @param [Jenkins::Model::Build] build the build which will begin
  # @param [Jenkins::Model::Listener] listener the listener for this build.
  def prebuild(build, listener)
    listener.info("Node Name: \"#{@node_name}\".")
    listener.info("Remote Host: \"#{@host}\"\nRemote Port: \"#{@port}\"\nRemote User: \"#{@user}\"")
    listener.info("Staging Dir: \"#{@stage_dir}\"")
    result = prepare_staging_dir
    listener.info("#{result}")
  end

  ##
  # Runs the step over the given build and reports the progress to the listener.
  #
  # @param [Jenkins::Model::Build] build on which to run this step
  # @param [Jenkins::Launcher] launcher the launcher that can run code on the node running this build
  # @param [Jenkins::Model::Listener] listener the listener for this build.
  def perform(build, launcher, listener)
    listener.info("Attempting to connect to \"#{@host}\" on port \"#{@port}\" as \"#{@user}\".")
    result = run_ssh_cmd
    listener.info("#{result}")
  end

  private
  
  def run_ssh_cmd
    result = "" 
    Net::SSH.start(@host, @user, connection_options) do |ssh|
      ssh.exec @ssh_cmds do |ch,stream,data|
        if stream == :stderr
          raise "FUCK! #{data}"
        else
          result << data
        end
      end
    end
    result
  end
  
  def prepare_staging_dir
    
    conn_opts = connection_options
     
    node_path = @stage_dir + '/' + @node_name    
    Net::SFTP.start(@host, @user, conn_opts) do |sftp|
      request = sftp.stat(@node_path) do |response|
        unless response.ok?
          sftp.mkdir(node_path, :permissions => 0700).wait
        end
      end
      request.wait
    end
  end
  
  def parse_conn_string(cstring)
    if cstring
      conn_attr = cstring.scan(/(.+)@([^:]+):?(\d+)?/).map { |u,h,p| { :user => u, :host => h, :port => p } }
      conn_attr[0]
    else
      conn_attr = { :user => nil, :host => nil, :port => nil }
    end
  end
  
  def connection_options
    connection_options = { :port => @port, :verbose => Logger::INFO }
          
    if @ssh_key.nil?
      connection_options[:password] = @ssh_pass
    else
      connection_options[:keys] = [@ssh_key]
      connection_options[:passphrase] = @ssh_pass
    end
    
    connection_options
  end

end