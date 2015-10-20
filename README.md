# Myxi

Myxi is a web socket server with a RabbitMQ backend to allow you to seemlessly
communicate between server & client using a defined protocol. All messages are
sent in JSON.

## Messaging philosophy

There are two key messages with Myxi, an action and an event.

### Actions

**An action is sent from the client to the server.** For example, when a client wants
to subscribe to an object, they will send an action message along with details
of the object they want to subscribe to. By default, only two actions are
available `Subscribe` and `Unsubscribe` which allow a client to receive messages
pushed to various channels by the server.

### Events

**An event is sent from the server to the client.** Events can be triggered in
one of two ways:

* _Socket Events:_ The web socket server itself may sent events to an individual client. These
  are likely to be related to the client's specific connection or an error.
  For example, you'll receive a `Welcome` event whenever you connect to the server
  and `Error` events are sent whenever an issue arises.

* _Application Events:_ Alternatively, events are triggered by your application
  via RabbitMQ. These are the events which you will want to be using most frequently.
  You'll likely trigger these in your application when an object's state changes
  and you need to notify a series of clients.

Right... that's all you need to know to get started really.

## Server-side Usage

You'll be needing a RabbitMQ backend to use Myxi. Fortunately, Viaduct has
just [added RabbitMQ support](https://blog.viaduct.io/rabbitmq-support/) so you
can easily get one of these online.

### Installation

Just install by adding to your Gemfile.

```ruby
gem 'myxi', '~> 1.0'
```

### Setting up an exchange

An exchange is something that your application can send messages to and it will
send them onwards to any clients who have subscribed to them. In your application
you may have an exchange where you'll post every change to every `widget`. Then,
whenever a widget changes you'll sent an event to the exchange along with a _routing key_
which identifies which specific widget was changed.

Before you can do this though, you'll need to define the exchange and specify
which users are permitted to subscribe to it.

```ruby
Myxi::Exchange.add(:widgets) do |routing_key, user|
  if widget = Widget.find_by_id(routing_key.to_i)
    widget.accessible_by?(user)
  else
    false
  end
end
```

In this example, I've added an exchange called `widgets` and defined a block
which will be executed to determine if the user is able to subscribe to the
routing key they have provided. This block must return a true or false value.
More information about authentication is provided in a moment.

### Sending events to exchanges

When your application wants to send an event, it just needs to a call the
`Myxi.push_event` method along with some details of which exchange it should be
sent to.

The `push_event` method accepts for arguments:

* the exchange name
* the routing key
* the name of the event
* a hash of additional parameters to sent

You can call this anywhere in your application. You may wish to add something
like the below to an Active Record model.

```ruby
after_save do
  if self.quantity_changed?
    Myxi.push_event('widgets', self.id, 'WidgetQtyChanged', {:quantity => self.quantity})
  end
end
```

Users can then subscribe to the `widgets` exchange with the appropriate routing
key will then be notified of this change and can do with it what they wish.

You can include whatever string value you wish as the event name but I'd recommend
sticking to simple characters like shown.

### Actions

By default your Myxi web socket server will only accept requests from a client
to `Subscribe` or `Unsubscribe` from an exchange. You can, however, add your
own actions which will be available to clients to call over the web socket
connection. You add actions in a similar way to exchanges.

```ruby
Myxi::Action.add(:SayHello) do |session, payload|
  session.send('HelloThere', :time => Time.now.to_i)
end
```

In this example, I've added an action which will cause the server to reply to
the client and say hello and provide the current server time. The `session.send`
method is similar to the `Myxi.push_event` method from earlier however it will
send a reply direct to the client for the session.

### Authentication

Anyone can connect to your web socket server so you need a mechanism to determine
who is logged in. To allow users to login, you'll need to configure an action
which the client can call once it has connected.

```ruby
Myxi::Action.add(:Authenticate) do |session, payload|
  if user_session = UserSession.active.find_by_token(params['session_token'])
    session.auth_object = user_session.user
    session.send('Authenticated', :username => user_session.user.username)
  else
    session.send('Error', :error => 'InvalidSessionToken')
  end
end
```

Here we've added an action called `Authenticate` which expects to receive a user's
session token. We then look this token up in our session table to verify it's valid
and then set the `session.auth_object` to our user. All future calls to actions
(including subscriptions) will now have access to this user. They will be logged in
for duration of the session. We send messages back to the client to confirm the
authentication was successful or an error if it wasn't.

You may also wish to implement a `Deauthenticate` action which sets it back to `nil`.

### Starting the web socket server

To start the web socket server, you just need to run the server's `run` method.
You may wish to just add a rake task to do this for your application.

```ruby
task :start_web_socket_server => :environment do
  require 'my_myxi_actions'
  Myxi::Server.new.run
end
```

The web socket server will listen on all interfaces on port 5005 however it will
respect the `MIXI_PORT` and `PORT` environment variables (in that order) if they
are provided. You can also pass options to the server when you initialize it.

```ruby
server = Myxi::Server.new(:port => '8055', :bind_address => '127.0.0.1')
server.run
```

### Connecting to RabbitMQ with Bunny

By default, Myxi will manage it's own connection to RabbitMQ and will connect to
the backend defined in the `RABBITMQ_URL` environment variable. If you would
rather manage the connection yourself, you can create your own Bunny instance (or use
an existing one). You can configure your own, as follows but by default you don't
need to do this. Be sure to do this early in your application's start up process.

```ruby
Myxi.bunny = Bunny.new("amqp://username:password@somehost/vhost")
Myxi.bunny.start
```

## Client-side Usage

You can connect to the web socket server itself using any web socket client that
you wish. All messages are sent to/from the server encoded as JSON so you'll need
to be able to decode/encode that too.

### Connecting

Your should connect your web socket client to your web socket server. For development,
you can just point it straight to your local port but in production you may
want to mount the socket server within your application's domain. In development,
you'll connect to something like this:

```
ws://localhost:5005/pushwss
```

As soon as you connect, you'll be sent a `Welcome` socket event message which will
contain your session ID. You'll probably have no use for the session ID in reality
but you never know - it may be useful if you wanted to implement a slightly different
authentication scheme.

```javascript
{
  "event":"Welcome",
  "payload":{
    "id":"186283241d812c21"
  }
}
```

### Sending action messages

To send action messages, you need to form the JSON and send it to the web socket
server. An action message is very similar to event messages but with an action.

```javascript
{
  "action":"Subscribe",
  "tag":"abc123abc",
  "payload":{
    "exchange":"widgets",
    "routing_key":1234
  }
}
```

* The `action` parameter is the name of the action.
* The `tag` parameter can be any value you wish. Any subsequent socket event
  messages (such as errors or confirmation) which relate to this action will also
  include the same tag.
* The `payload` is another hash which contains data which is needed for the action.

Using this technique, you can send whatever messages you wish to the server.

### Subscribing & Unsubscibing from Exchanges

To subscribe to an exchange, you just send a `Subscribe` action along with the
`exchange` and `routing_key` in the payload. If the subscription is successful,
you'll receive a `Subscribed` socket event message. If not, you'll receive an error.

Unsubscribing is the same as subscibing. Just call the `Unsubscribe` method with
the name of the exchange and the routing key which you want to unsubscribe from.
As above, you'll receive an `Unsubscribe` socket event message when you have been
unsubscribed.

When unsubscribing, you may optionally choose to exclude the routing key to
unsubscribe from a whole exchange or exclude both exchange & routing key to
unsubscribe from everything which has previously been subscribed to.

### Errors

If an issue arises, you'll receive a socket event message with the `Error` plus
some details of the error in the payload. For example:

```javascript
{
  "event":"Error",
  "tag":"xxx",
  "payload":{
    "error":"InvalidExchangeName"
  }
}
```
