Myxi::Action.add(:Subscribe) do |session, payload|
  session.subscribe(payload['exchange'], payload['routing_key'])
end

Myxi::Action.add(:Unsubscribe) do |session, payload|
  if payload['exchange'] && payload['routing_key']
    session.unsubscribe(payload['exchange'], payload['routing_key'])
  elsif payload['exchange'] && payload['routing_key'].nil?
    session.unsubscribe_all_for_exchange(payload['exchange'])
  else
    session.unsubscribe_all
  end
end
