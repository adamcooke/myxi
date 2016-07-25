window.Myxi ||= {}
class Myxi.Subscription

  @keyFor: (exchange, routingKey)->
    key = exchange
    if routingKey?
      key = "#{key}::#{routingKey}"
    key

  constructor: (connection, exchange, routingKey)->
    @connection = connection
    @exchange = exchange
    @routingKey = routingKey
    @subscribed = false
    @reconnect = true
    @callbacks = {}
    @messageHandlers = {}
    @subscribe() if @connection.connected

  subscribe: ()->
    @connection.sendAction('Subscribe', {'exchange': @exchange, 'routing_key': @routingKey})

  key: ()->
    Myxi.Subscription.keyFor(@exchange, @routingKey)

  unsubscribe: ()->
    if @connection.sendAction('Unsubscribe', {'exchange': @exchange, 'routing_key': @routingKey})
      @subscribed = false
      @reconnect = false
      true
    else
      false

  addMessageHandler: (name, handler, param)->
    @messageHandlers[name] = {handler: handler, param: param}

  removeMessageHandler: (name)->
    if @messageHandlers[name]
      delete @messageHandlers[name]
      true
    else
      false

  on: (event, callback)->
    @callbacks[event] ||= []
    @callbacks[event].push(callback)

  _isSubscribed: ()->
    console.log "Subscribed to #{@key()}"
    @subscribed = true

  _isUnsubscribed: ()->
    console.log "Unsubscribed from #{@key()}"
    @subscribed = false

  _receiveMessage: (event, payload, tag)->
    if callbacks = @callbacks[event]
      for callback in callbacks
        callback.call(this, payload, tag)
    for handler, opts of @messageHandlers
      opts.handler.call(opts.param, this, event, payload, tag)
