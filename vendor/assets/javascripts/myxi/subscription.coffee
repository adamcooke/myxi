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
