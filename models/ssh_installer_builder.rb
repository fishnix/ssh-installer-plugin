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
  attr_accessor :forward_agent
  
  
  # Invoked with the form parameters when this extension point
  # is created from a configuration screen.
  def initialize(attrs = {})
    @node_name = attrs['node_name']
    @conn_string = attrs['conn_string']
    @forward_agent = attrs['forward_agent']
    
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
    listener.info("Forward Agent: \"#{@forward_agent}\"")

    staging_dir = @stage_dir + '/' + @node_name
    listener.info("Staging Dir: \"#{staging_dir}\"")
    listener.info("ENV: #{setenv}")
    
    result = prepare_staging_dir(staging_dir)
    listener.info("#{result}")
    
    transfer_workspace(build.workspace.to_s, staging_dir)
  end

  ##
  # Runs the step over the given build and reports the progress to the listener.
  #
  # @param [Jenkins::Model::Build] build on which to run this step
  # @param [Jenkins::Launcher] launcher the launcher that can run code on the node running this build
  # @param [Jenkins::Model::Listener] listener the listener for this build.
  def perform(build, launcher, listener)
    #listener.info("#{build.class.instance_methods}")
    build_params = filter_for_node_name(build.native.getBuildVariables())
    listener.info("#{build_params}")
    
    listener.info("Attempting to connect to \"#{@host}\" on port \"#{@port}\" as \"#{@user}\".")
    result = run_ssh_cmd
    listener.info("#{result}")
  end

  private
  
  def parse_conn_string(cstring)
    if cstring
      conn_attr = cstring.scan(/(.+)@([^:]+):?(\d+)?/).map { |u,h,p| { :user => u, :host => h, :port => p } }
      conn_attr[0]
    else
      conn_attr = { :user => nil, :host => nil, :port => nil }
    end
  end
  
  def connection_options
    connection_options = {  :port => @port, 
                            :forward_agent => @forward_agent, 
                            :verbose => Logger::INFO 
                          }
          
    if @ssh_key.nil?
      connection_options[:password] = @ssh_pass
    else
      connection_options[:keys] = [@ssh_key]
      connection_options[:passphrase] = @ssh_pass
    end
    
    connection_options
  end
  
  def filter_for_node_name(build_params)
    build_params.each do |k,v|
      build_params[k] = v.gsub!('${node_name}', @node_name)
    end
  end
  
  def filter_for_build_params(build_params)
    build_params.each_key do |k,v|
      var = '${' + k + '}'
      @ssh_cmds.gsub!(var,v) unless @ssh_cmds.nil?
    end
  end
  
  def prepare_staging_dir(staging_dir)
    Net::SFTP.start(@host, @user, connection_options) do |sftp|
      request = sftp.stat(staging_dir) do |response|
        return unless response.ok?
      end
      request.wait
      
      rm_rf(sftp, staging_dir)
    end
  end
  
  def transfer_workspace(workspace, staging_dir)
    Net::SFTP.start(@host, @user, connection_options) do |sftp|      
      sftp.upload!(workspace, staging_dir)
    end
  end
  
  def run_ssh_cmd
    result = ""
    Net::SSH.start(@host, @user, connection_options) do |ssh|
      ssh.exec(setenv + ';' + @ssh_cmds) do |ch,stream,data|
        if stream == :stderr
          raise "FUCK! #{data}"
        else
          result << data
        end
      end
    end
    result
  end
  
  def setenv
    @ssh_env.split.join(';')
  end
  
  def rm_rf(sftp, dir)
    sftp.opendir(dir) do |response|
       raise "failed to open directory: " + dir unless response.ok?

       loop do
         request = sftp.readdir(response[:handle]).wait
         break if request.response.eof?
         raise "failed to read directory: " + dir unless request.response.ok?

         request.response[:names].each do |entry|
           next if entry.name == '.' or entry.name == '..'

           if entry.file? or entry.symlink?
             sftp.remove!(dir + '/' + entry.name)
           elsif entry.directory?
             rm_rf(sftp, dir + '/' + entry.name)
           else
              raise "Couldn't determine type for " + entry.name
           end
         end
       end
       sftp.rmdir!(dir)
       sftp.close(response[:handle])
     end
  end

end