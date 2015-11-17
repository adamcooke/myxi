Myxi::Action.add(:Subscribe) do |session, payload|
  if payload['routing_keys'].is_a?(Array)
    for key in payload['routing_keys']
      session.subscribe(payload['exchange'], key)
    end
  else
    session.subscribe(payload['exchange'], payload['routing_key'])
  end
end

Myxi::Action.add(:Unsubscribe) do |session, payload|
  if payload['exchange'] && payload['routing_key']
    if payload['routing_keys'].is_a?(Array)
      for key in payload['routing_keys']
        session.unsubscribe(payload['exchange'], key)
      end
    else
      session.unsubscribe(payload['exchange'], payload['routing_key'])
    end
  elsif payload['exchange'] && payload['routing_key'].nil?
    session.unsubscribe_all_for_exchange(payload['exchange'])
  else
    session.unsubscribe_all
  end
end

Myxi::Action.add(:ListSubscriptions) do |session, payload|
  session.send "YourSubscriptions", :subscriptions => session.subscriptions
end
