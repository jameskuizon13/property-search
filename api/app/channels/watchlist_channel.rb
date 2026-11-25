# One stream per signed-in user. PropertyChangeNotifier broadcasts a
# property's changes to each of its watchers' streams, so a user only ever
# receives their own, and holds one subscription however many properties they
# watch. Clients only listen; there are no actions.
class WatchlistChannel < ApplicationCable::Channel
  private

  # Private, like ActionCable's own callback: every public method on a channel
  # is an action a client can `perform`, and a public `subscribed` would let it
  # stream the same updates twice.
  def subscribed
    # The connection already rejects anonymous sockets; this is a second check.
    return reject unless current_user

    stream_for current_user
  end
end
