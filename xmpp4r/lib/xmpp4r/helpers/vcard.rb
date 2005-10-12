# =XMPP4R - XMPP Library for Ruby
# License:: Ruby's license (see the LICENSE file) or GNU GPL, at your option.
# Website::http://home.gna.org/xmpp4r/

require 'xmpp4r/iq'

module Jabber
  module Helpers
    ##
    # The Vcard helper retrieves vCards
    class Vcard
      ##
      # Initialize a new Vcard helper
      def initialize(stream)
        @stream = stream
      end

      ##
      # Retrieve vCard of an entity
      #
      # Raises exception upon retrieval error, please catch that!
      #
      # Usage of Threads is suggested here as vCards can be very
      # big (see <tt>/iq/vCard/PHOTO/BINVAL</tt>).
      #
      # jid:: [Jabber::JID] or nil (should be stripped, nil for the client's own vCard)
      # result:: [Jabber::IqVcard] or nil (nil results may be handled as empty vCards)
      def get(jid=nil)
        res = nil
        request = Iq.new(:get, jid)
        request.from = @stream.jid  # Enable components to use this
        request.add(IqVcard.new)
        @stream.send_with_id(request) { |answer|
          # No check for sender or queryns needed (see send_with_id)
          if answer.type == :result
            res = answer.vcard
            true
          elsif answer.type == :error
            res = answer.first_element('error')
            true
          else
            false
          end
        }
        if res.kind_of?(Error)
          raise "Error getting vCard: #{res.error}, #{res.text}"
        end
        res
      end

      ##
      # Set your own vCard (Clients only)
      #
      # Raises exception when setting fails
      #
      # Usage of Threads suggested here, too. The function
      # waits for approval from the server.
      #
      # iqvcard:: [Jabber::IqVcard]
      def set(iqvcard)
        iq = Iq.new(:set)
        iq.add(iqvcard)

        error = nil
        @stream.send_with_id(iq) { |answer|
          if answer.type == :result
            true
          elsif answer.type == :error
            error = answer.first_element('error')
            true
          else
            false
          end
        }
        unless error.nil?
          raise "Error setting vCard: #{res.error}, #{res.text}"
        end
      end

      ##
      # Quickly initialize a Vcard helper and get
      # a vCard. See Vcard#get
      def Vcard.get(stream, jid=nil)
        Vcard.new(stream).get(jid)
      end

      ##
      # Quickly initialize a Vcard helper and set
      # your vCard. See Vcard#set
      def Vcard.set(stream, iqvcard)
        Vcard.new(stream).set(iqvcard)
      end
    end
  end
end
