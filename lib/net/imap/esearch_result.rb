# frozen_string_literal: true

module Net
  class IMAP
    # An Extended SEARCH result, eturned by Net::IMAP#search or IMAP#uid_search,
    # when the server supports +ESEARCH+ and a return option is specified.
    # IMAP4rev2 servers will *always* return ESearchResult instead of
    # SearchResult.  ESearchResult will also be returned by IMAP#sort and
    # IMAP#uid_sort when the server supports +ESORT+ and return optiuns are
    # specified.
    class ESearchResult < Struct.new(:tag, :uid, :data)

      ##
      # method: tag
      # :call-seq: tag -> string or nil
      #
      # The tag of the command that caused the response to be returned.
      #
      # If it is missing, then the response was not caused by a particular IMAP
      # command.

      ##
      # method: uid
      # :call-seq: uid -> boolean
      #
      # When true, all #data in the ESEARCH response refers to UIDs; otherwise,
      # all returned #data refers to message sequence numbers.

      ##
      # method: data
      # :call-seq: data -> hash
      #
      # Search return data, which can also be retrieved by #min, #max, #all,
      # #count, #modseq, and other methods.  Most return data tags are initiated
      # by a return option of the same name.

      ##
      # The lowest message number/UID that satisfies the SEARCH criteria.
      # Returns nil when the associated search command has no results, or when
      # the +MIN+ return option wasn't specified.
      #
      # See ESEARCH (RFC4731 §3.1) or IMAP4rev2 (RFC9051 §6.4.4)
      def min;        data["MIN"]        end

      # The highest message number/UID that satisfies the SEARCH criteria.
      # Returns nil when the associated search command has no results, or when
      # the +MAX+ return option wasn't specified.
      #
      # See ESEARCH (RFC4731 §3.1) or IMAP4rev2 (RFC9051 §6.4.4)
      def max;        data["MAX"]        end

      # A SequenceSet containing all message numbers/UIDs that satisfy the
      # SEARCH criteria.  Returns +nil+ when the associated search command has
      # no results, or when the +ALL+ return option wasn't specified.
      #
      # See ESEARCH (RFC4731 §3.1) or IMAP4rev2 (RFC9051 §6.4.4)
      def all;        data["ALL"]        end

      # Returns the number of messages that satisfy the SEARCH criteria.
      # Returns +nil+ when the associated search command has no results.
      #
      # See ESEARCH (RFC4731 §3.1) or IMAP4rev2 (RFC9051 §6.4.4)
      def count;      data["COUNT"]      end

      # The highest +mod-sequence+ of all messages in the set that satisfy the
      # SEARCH criteria and result options.  Returns +nil+ when the associated
      # search command has no results.
      #
      # See CONDSTORE (RFC4731 §3.2, RFC7162 §3.1.5)
      def modseq;     data["MODSEQ"]     end

      # Notification of updates, inserting messages into the result list for the
      # command issued with #tag.
      #
      # See CONTEXT=SEARCH or CONTEXT=SORT (RFC5267 §4.3)
      def addto;      data["ADDTO"]      end

      # Notification of updates, removing messages into the result list for the
      # command issued with #tag.
      #
      # See CONTEXT=SEARCH or CONTEXT=SORT (RFC5267 §4.3)
      def removefrom; data["REMOVEFROM"] end

      # Return a subset of the message numbers/UIDs that satisfy the SEARCH
      # criteria.
      #
      # See CONTEXT=SEARCH or CONTEXT=SORT (RFC5267 §4.4) or
      # PARTIAL (I-D.ietf-extra-imap-partial §3.1)
      def partial;    data["PARTIAL"]    end

      # Return a relevancy score for each message that satisfies the SEARCH
      # criteria.
      #
      # See SEARCH=FUZZY (RFC6203 §4)
      def relevancy;  data["RELEVANCY"]  end

    end
  end
end
