require 'forwardable'
require 'json'
require 'socket'
require 'zk'


class JonesClient
  extend Forwardable
  attr_accessor :data
  def_delegators :@data, :[]

  def initialize(options = {})
    @data = nil
    @callbacks = []
    @conf_sub = nil
    @conf_path = nil
    logger = Logger.new(STDOUT)

    parse_options(options)
    setup_zk
    read_nodemap
  end

  def register_callback(&block)
    @callbacks += [block]
  end

  private

  def nodemap_changed(event)
    if event.node_changed?
      read_nodemap
    else
      logger.error("Unknown ZK node event: #{event.inspect}")
    end
  end

  def read_nodemap
    data = @zk.get(nodemap_path, :watch => true).first
    if data.nil?
      conf_path = conf_root
    else
      mapping = Hash[data.split("\n").map {|s| s.split(' -> ') }]
      conf_path = mapping.fetch(@host, conf_root)
    end

    setup_conf(conf_path)
  end

  def setup_conf(conf_path)
    if conf_path != @conf_path
      # path changed so we need to register a new handler
      @conf_path = conf_path
      @conf_sub.unsubscribe unless @conf_sub.nil?
      @conf_sub = @zk.register(@conf_path) { |event| conf_changed(event) }
      read_conf
    end
  end

  def conf_changed(event)
    if event.node_changed?
      read_conf
    else
      logger.error("Unknown ZK node event: #{event.inspect}")
    end
  end

  def read_conf()
    @data = JSON.load(@zk.get(@conf_path, :watch => true).first)
    @callbacks.each { |cb| cb.call(@data) }
  end

  def setup_zk
    @zk = ZK.new(@zkservers) if @zkservers
    @zk.on_expired_session { setup_zk }
    @zk.register(nodemap_path, :only => :changed) { |event| nodemap_changed(event) }
    # reset watch in case of disconnect
    @zk.on_connected { read_nodemap }
  end

  def parse_options(options)
    @zk, @zkservers = options.values_at(:zk, :zkservers)
    if [@zk, @zkservers].all? || [@zk, @zkservers].none?
      raise ArgumentError, 'must specify :zk or :zkservers'
    end

    @service = options[:service]
    @host = options.fetch(:host, Socket.gethostname)
    @zkroot = "/services/#{options[:service]}"
  end

  def nodemap_path
    "#{@zkroot}/nodemaps"
  end

  def conf_root
    "#{@zkroot}/conf"
  end
end


#zk = ZK.new('localhost:2181')

jc = JonesClient.new(:zkservers => 'localhost:2181', :service => 'test')
jc.register_callback { |data| puts data['field'] }
puts jc['field']

sleep(20)
puts jc['field']
