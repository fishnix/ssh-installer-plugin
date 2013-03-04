require 'rubygems'
require 'net/ssh'
require_relative 'net_ssh'

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
  attr_accessor :xfer_workspace
  attr_accessor :forward_agent
  attr_accessor :install_properties
  
  
  # Invoked with the form parameters when this extension point
  # is created from a configuration screen.
  def initialize(attrs = {})
    @node_name = attrs['node_name']
    @conn_string = attrs['conn_string']
    @forward_agent = attrs['forward_agent']
    @xfer_workspace = attrs['xfer_workspace']
    
    conn_attr = parse_conn_string attrs['conn_string']
    @host = conn_attr[:host]
    @port = conn_attr[:port] ||= 22
    @user = conn_attr[:user]
    
    @ssh_key =  attrs['ssh_key']    == "" ? nil : attrs['ssh_key']
    @ssh_pass = attrs['ssh_pass']   == "" ? nil : attrs['ssh_pass']
    
    @ssh_env =  attrs['ssh_env']
    @ssh_cmds = attrs['ssh_cmds']
    
    @stage_dir = attrs['stage_dir'] == "" ? './' : attrs['stage_dir']
    
    @install_properties = attrs['install_properties'] == "" ? 'install.properties' : attrs['install_properties']
  end

  ##
  # Runs before the build begins
  #
  # @param [Jenkins::Model::Build] build the build which will begin
  # @param [Jenkins::Model::Listener] listener the listener for this build.
  def prebuild(build, listener)
    listener.info("\nStarting Prebuild:")
    listener.info("Node Name: \"#{@node_name}\".")
    listener.info("Remote Host: \"#{@host}\"\nRemote Port: \"#{@port}\"\nRemote User: \"#{@user}\"")
    listener.info("Forward Agent: \"#{@forward_agent}\"")
    listener.info("Transfer Workspace: \"#{@xfer_workspace}\"")

    staging_dir = @stage_dir + '/' + @node_name
    listener.info("Staging Dir: \"#{staging_dir}\"")
    listener.info("Environment:\n" + setenv + "\n")
    
    listener.info("Preparing staging directory.\n")
    result = prepare_staging_dir(staging_dir)
    
    if @xfer_workspace 
      listener.info("Starting to transfer workspace.")
      transfer_workspace(build.workspace.to_s, staging_dir)
    else
      listener.info("Not transfering workspace, disabled by plugin.\n")
    end
    
  end

  ##
  # Runs the step over the given build and reports the progress to the listener.
  #
  # @param [Jenkins::Model::Build] build on which to run this step
  # @param [Jenkins::Launcher] launcher the launcher that can run code on the node running this build
  # @param [Jenkins::Model::Listener] listener the listener for this build.
  def perform(build, launcher, listener)
    build_params_unfiltered = build.native.getBuildVariables()
    build_params = filter_for_node_name(build_params_unfiltered)
    listener.info("Build Params: \n#{build_params}\n")
    
    staging_dir = @stage_dir + '/' + @node_name
    
    listener.info("Attempting to write install properties to #{@install_properties}.\n")
    write_install_props(staging_dir, build_params)
    
    command = filter_ssh_command(build_params)
    listener.info("Generated filtered command: \n===== \n" + command + "\n===== \n")

    listener.info("Attempting to connect to \"#{@host}\" on port \"#{@port}\" as \"#{@user}\".")
    result = run_ssh_cmd(staging_dir, command)
    
    listener.info("SSH CMD Result: #{result}")
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
      build_params[k] = v.gsub('${node_name}', @node_name)
    end
    build_params
  end
  
  def filter_ssh_command(build_params)
    command = String.new(@ssh_cmds)
    
    build_params.each do |k,v|
      var = '${' + k + '}'
      unless v.nil? 
        command.gsub!(var,v) unless command.nil?
      end
    end

    command.gsub!('${node_name}', @node_name) unless command.nil?
  end
  
  # Prepare the staging directory on the target
  #   1. Check if dir exists, if it does, blast it
  #   2. Create staging directory
  #   3. Check that dir exists
  def prepare_staging_dir(staging_dir)
    Net::SFTP.start(@host, @user, connection_options) do |sftp|      
      if sftp.exists?(staging_dir)
        rm_rf(sftp,staging_dir)
      end
      
      response = sftp.mkdir!(staging_dir)
      raise "Failed to create staging directory " + staging_dir unless response.ok?
      
      raise "Staging directory: " + staging_dir + " doesnt exist but should." unless sftp.exists?(staging_dir)
      
    end
  end
  
  # recursively transfer workspace to the staging dir
  def transfer_workspace(workspace, staging_dir)
    Net::SFTP.start(@host, @user, connection_options) do |sftp|      
      sftp.upload!(workspace, staging_dir)
    end
  end
  
  # writes build props into install.properties
  def write_install_props(dir,props)
    props_string = props.map{ |k,v| "#{k}=#{v}"}.join("\n")
    
    file = dir + "/" + @install_properties
    Net::SFTP.start(@host, @user, connection_options) do |sftp|
      handle = sftp.open!(file, "w")
      sftp.write!(handle, 0, props_string)
      sftp.close!(handle)
    end
  end
  
  # run a remote SSH command
  def run_ssh_cmd(staging_dir, command)
    result = ""
    Net::SSH.start(@host, @user, connection_options) do |ssh|
      ssh.exec('cd ' + staging_dir + '&&' + setenv + ';' + command) do |ch,stream,data|
        if stream == :stderr
          raise "FUCK! #{data}"
        else
          result << data
        end
      end
    end
    result
  end
  
  # join the array of env vars with semicolon
  def setenv
    @ssh_env.split.join(';')
  end
  
  # recursively delete a directory,
  # takes sftp session object + directory name
  def rm_rf(sftp, dir)
    handle = sftp.opendir!(dir)
  
    loop do
     request = sftp.readdir(handle).wait
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
       
    sftp.close!(handle)
    sftp.rmdir!(dir)
  end
end