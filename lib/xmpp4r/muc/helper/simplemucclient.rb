# =XMPP4R - XMPP Library for Ruby
# License:: Ruby's license (see the LICENSE file) or GNU GPL, at your option.
# Website::http://home.gna.org/xmpp4r/

require 'xmpp4r/delay/x/delay'
require 'xmpp4r/muc/helper/mucclient'
require 'xmpp4r/muc/iq/mucadminitem'

module Jabber
  module MUC
    ##
    # This class attempts to implement a lot of complexity of the
    # Multi-User Chat protocol. If you want to implement JEP0045
    # yourself, use Jabber::MUC::MUCClient for some minor
    # abstraction.
    #
    # Minor flexibility penalty: the on_* callbacks are no
    # CallbackLists and may therefore only used once. A second
    # invocation will overwrite the previous set up block.
    #
    # *Hint:* the parameter time may be nil if the server didn't
    # send it.
    #
    # Example usage:
    #   my_muc = Jabber::MUC::SimpleMUCClient.new(my_client)
    #   my_muc.on_message { |time,nick,text|
    #     puts (time || Time.new).strftime('%I:%M') + " <#{nick}> #{text}"
    #   }
    #   my_muc.join(Jabber::JID.new('jdev@conference.jabber.org/XMPP4R-Bot'))
    #
    # Please take a look at Jabber::MUC::MUCClient for
    # derived methods, such as MUCClient#join, MUCClient#exit,
    # ...
    class SimpleMUCClient < MUCClient
      ##
      # Initialize a SimpleMUCClient
      # stream:: [Stream] to operate on
      # jid:: [JID] room@component/nick
      # password:: [String] Optional password
      def initialize(stream)
        super

        @room_message_block = nil
        @message_block = nil
        @private_message_block = nil
        @subject_block = nil

        @subject = nil

        @join_block = nil
        add_join_callback(999) { |pres|
          # Presence time
          time = nil
          pres.each_element('x') { |x|
            if x.kind_of?(Delay::XDelay)
              time = x.stamp
            end
          }

          # Invoke...
          on_join(time, pres)
          false
        }

        @leave_block = nil
        @self_leave_block = nil
        add_leave_callback(999) { |pres|
          # Presence time
          time = nil
          pres.each_element('x') { |x|
            if x.kind_of?(Delay::XDelay)
              time = x.stamp
            end
          }

          # Invoke...
          if pres.from == jid
            on_self_leave(time)
          else
            on_leave(time, pres)
          end
          false
        }
      end

      private

      def handle_message(msg)
        super

        # Message time (e.g. history)
        time = nil
        msg.each_element('x') { |x|
          if x.kind_of?(Delay::XDelay)
            time = x.stamp
          end
        }
        sender_nick = msg.from.resource


        if msg.subject
          @subject = msg.subject
          on_subject(time, sender_nick, @subject)
        end

        if msg.body
          if sender_nick.nil?
            on_room_message(time, msg)
          else
            if msg.type == :chat
              on_private_message(time, msg)
            elsif msg.type == :groupchat
              on_message(time, msg)
            else
              # ...?
            end
          end
        end
      end

      public

      ##
      # Room subject/topic
      # result:: [String] The subject
      def subject
        @subject
      end

      ##
      # Change the room's subject/topic
      #
      # This will not be reflected by SimpleMUCClient#subject
      # immediately, wait for SimpleMUCClient#on_subject
      # s:: [String] New subject
      def subject=(s)
        msg = Message.new
        msg.subject = s
        send(msg)
      end

      ##
      # Send a simple text message
      # text:: [String] Message body
      # to:: [String] Optional nick if directed to specific user
      def say(text, to=nil)
        send(Message.new(nil, text), to)
      end

      ##
      # Request the MUC to invite users to this room
      #
      # Sample usage:
      #   my_muc.invite( {'wiccarocks@shakespeare.lit/laptop' => 'This coven needs both wiccarocks and hag66.',
      #                   'hag66@shakespeare.lit' => 'This coven needs both hag66 and wiccarocks.'} )
      # recipients:: [Hash] of [JID] => [String] Reason
      def invite(recipients)
        msg = Message.new
        x = msg.add(XMUCUser.new)
        recipients.each { |jid,reason|
          x.add(XMUCUserInvite.new(jid, reason))
        }
        send(msg)
      end

      ##
      # Administratively remove one or more users from the room.
      #
      # Will wait for response, possibly raising ServerError
      #
      # Sample usage:
      #   my_muc.kick 'pistol', 'Avaunt, you cullion!'
      #   my_muc.kick(['Bill', 'Linus'], 'Stop flaming')
      #
      # recipients:: [Array] of, or single [String]: Nicks
      # reason:: [String] Kick reason
      def kick(recipients, reason)
        recipients = [recipients] unless recipients.kind_of? Array
        items = recipients.collect { |recipient|
          item = IqQueryMUCAdminItem.new
          item.nick = recipient
          item.role = :none
          item.reason = reason
          item
        }
        send_affiliations(items)
      end

      ##
      # Administratively ban one or more user jids from the room.
      #
      # Will wait for response, possibly raising ServerError
      #
      # Sample usage:
      #   my_muc.ban 'pistol@foobar.com', 'Avaunt, you cullion!'
      #
      # recipients:: [Array] of, or single [String]: JIDs
      # reason:: [String] Ban reason
      def ban(recipients, reason)
        recipients = [recipients] unless recipients.kind_of? Array
        items = recipients.collect { |recipient|
          item = IqQueryMUCAdminItem.new
          item.jid = recipient
          item.affiliation = :outcast
          item.reason = reason
          item
        }
        send_affiliations(items)
      end

      ##
      # Unban one or more user jids for the room.
      #
      # Will wait for response, possibly raising ServerError
      #
      # Sample usage:
      #   my_muc.unban 'pistol@foobar.com'
      #
      # recipients:: [Array] of, or single [String]: JIDs
      def unban(recipients)
        recipients = [recipients] unless recipients.kind_of? Array
        items = recipients.collect { |recipient|
          item = IqQueryMUCAdminItem.new
          item.jid = recipient
          item.affiliation = :none
          item
        }
        send_affiliations(items)
      end

      ##
      # Promote one or more users in the room to moderator.
      #
      # Will wait for response, possibly raising ServerError
      #
      # Sample usage:
      #   my_muc.promote 'pistol'
      #
      # recipients:: [Array] of, or single [String]: Nicks
      def promote(recipients)
        recipients = [recipients] unless recipients.kind_of? Array
        items = recipients.collect { |recipient|
          item = IqQueryMUCAdminItem.new
          item.nick = recipient
          item.role = :moderator
          item
        }
        send_affiliations(items)
      end

      ##
      # Demote one or more users in the room to participant.
      #
      # Will wait for response, possibly raising ServerError
      #
      # Sample usage:
      #   my_muc.demote 'pistol'
      #
      # recipients:: [Array] of, or single [String]: Nicks
      def demote(recipients)
        recipients = [recipients] unless recipients.kind_of? Array
        items = recipients.collect { |recipient|
          item = IqQueryMUCAdminItem.new
          item.nick = recipient
          item.role = :participant
          item
        }
        send_affiliations(items)
      end

      ##
      # Block to be invoked when a message *from* the room arrives
      #
      # Example:
      #   Astro has joined this session
      # block:: Takes two arguments: time, text
      def on_room_message(time = nil, msg = nil, &block)
        if block_given?
          @room_message_block = block
        elsif @room_message_block
          @room_message_block.call(time, msg.body)
        end
      end

      ##
      # Block to be invoked when a message from a participant to
      # the whole room arrives
      # block:: Takes three arguments: time, sender nickname, text
      def on_message(time = nil, msg = nil, &block)
        if block_given?
          @message_block = block
        elsif @message_block
          @message_block.call(time, msg.from.resource, msg.body)
        end
      end

      ##
      # Block to be invoked when a private message from a participant
      # to you arrives.
      # block:: Takes three arguments: time, sender nickname, text
      def on_private_message(time = nil, msg = nil, &block)
        if block_given?
          @private_message_block = block
        elsif @private_message_block
          @private_message_block.call(time, msg.from.resource, msg.body)
        end
      end

      ##
      # Block to be invoked when somebody sets a new room subject
      # block:: Takes three arguments: time, nickname, new subject
      def on_subject(time = nil, sender_nick = nil, &block)
        if block_given?
          @subject_block = block
        elsif @subject_block
          @subject_block.call(time, sender_nick, @subject)
        end
      end

      ##
      # Block to be called when somebody enters the room
      #
      # If there is a non-nil time passed to the block, chances
      # are great that this is initial presence from a participant
      # after you have joined the room.
      # block:: Takes two arguments: time, nickname
      def on_join(time = nil, pres = nil, &block)
        if block_given?
          @join_block = block
        elsif @join_block
          @join_block.call(time, pres.from.resource)
        end
      end

      ##
      # Block to be called when somebody leaves the room
      # block:: Takes two arguments: time, nickname
      def on_leave(time = nil, pres = nil, &block)
        if block_given?
          @leave_block = block
        elsif @leave_block
          @leave_block.call(time, pres.from.resource)
        end
      end

      ##
      # Block to be called when *you* leave the room
      #
      # Deactivation occurs *afterwards*.
      # block:: Takes one argument: time
      def on_self_leave(time = nil, &block)
        if block_given?
          @self_leave_block = block
        elsif @self_leave_block
          @self_leave_block.call(time)
        end
      end
    end
  end
end
