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
  attr_accessor :xfer_workspace
  attr_accessor :forward_agent
  
  
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
    listener.info("Transfer Workspace: \"#{@xfer_workspace}\"")

    staging_dir = @stage_dir + '/' + @node_name
    listener.info("Staging Dir: \"#{staging_dir}\"")
    listener.info("ENV: #{setenv}")
    
    listener.info("Preparing staging directory.")
    result = prepare_staging_dir(staging_dir)
    
    if @xfer_workspace 
      listener.info("Starting to transfer workspace.")
      transfer_workspace(build.workspace.to_s, staging_dir)
    else
      listener.info("Not transfering workspace, disabled by plugin.")
    end
    
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
    listener.info("Build Params: #{build_params}")
    
    listener.info("Attempting to connect to \"#{@host}\" on port \"#{@port}\" as \"#{@user}\".")
    result = run_ssh_cmd
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
      build_params[k] = v.gsub!('${node_name}', @node_name)
    end
  end
  
  def filter_for_build_params(build_params)
    build_params.each_key do |k,v|
      var = '${' + k + '}'
      @ssh_cmds.gsub!(var,v) unless @ssh_cmds.nil?
    end
  end
  
  # Prepare the staging directory on the target
  #   1. Check if dir exists, if it does, blast it
  #   2. Create staging directory
  #   3. Check that dir exists
  def prepare_staging_dir(staging_dir)
    Net::SFTP.start(@host, @user, connection_options) do |sftp|
      puts "Preparing staging dir: " + staging_dir
      
      if exists?(sftp,staging_dir)
        puts "exists."
        rm_rf(sftp, staging_dir)
      else
        puts "doesnt"
      end
      
      response = sftp.mkdir! "#{staging_dir}"
      raise "Failed to create staging directory " + staging_dir unless response.ok?
      
      raise "Staging directory: " + staging_dir + " doesnt exist but should." unless exists?(sftp,staging_dir)
      
      
      # begin
      #   staging_dir_attrs = sftp.stat!(staging_dir)
      #   rm_rf(sftp, staging_dir)
      #   
      #   puts "Creating staging dir."
      #   # (re)create the staging directory
      #   response = sftp.mkdir! "#{staging_dir}"
      #   raise "Failed to create staging directory " + staging_dir unless response.ok?
      #   
      # rescue
      #   puts "Creating staging dir."
      # 
      #   # (re)create the staging directory
      #   response = sftp.mkdir! "#{staging_dir}"
      #   raise "Failed to create staging directory " + staging_dir unless response.ok?
      # end
      
      # make sure the directory exists now
      # response = sftp.stat! "#{staging_dir}"
      # raise "Staging directory: " + staging_dir + " doesnt exist." unless response.directory?
      
      # delete staging directory recursively if it exists
      # staging_dir_attrs = sftp.stat!(staging_dir)
      # request = sftp.stat!(staging_dir) do |response|
      #   if response.ok?
      #     puts "Staging dir: #{staging_dir} appears to exist, removing it."
      #     rm_rf(sftp, staging_dir)
      #   end
      # end
      
      # (re)create the staging directory
      # response = sftp.mkdir! "#{staging_dir}"
      # raise "Failed to create staging directory " + staging_dir unless response.ok?
      
      # make sure the directory exists now
      # response = sftp.stat! "#{staging_dir}"
      # raise "Staging directory: " + staging_dir + " doesnt exist." unless response.directory?
    end
  end
  
  # recursively transfer workspace to the staging dir
  def transfer_workspace(workspace, staging_dir)
    Net::SFTP.start(@host, @user, connection_options) do |sftp|      
      sftp.upload!(workspace, staging_dir)
    end
  end
  
  # run a remote SSH command
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
  
  # join the array of env vars with semicolon
  def setenv
    @ssh_env.split.join(';')
  end
  
  # returns the stat object if exists, false if not
  # takes sftp session object + file/dir name
  def exists?(sftp,dir)
    begin
      sftp.stat!(dir)
    rescue Net::SFTP::StatusException => e 
      raise unless e.code == 2
      false
    end
  end
  
  # recursively delete a directory,
  # takes sftp session object + directory name
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