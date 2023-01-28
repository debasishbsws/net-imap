# frozen_string_literal: true

module Net
  class IMAP

    ##
    # An IMAP {sequence set}[https://www.rfc-editor.org/rfc/rfc9051.html#section-4.1.1],
    # is a set of message sequence numbers or unique identifier numbers
    # ("UIDs").  It contains numbers and ranges of numbers.  The numbers are all
    # non-zero unsigned 32-bit integers and one special value, <tt>*</tt>, that
    # represents the largest value in the mailbox.
    #
    # === Creating sequence sets
    #
    # SequenceSet is used to validate and format arguments to many different
    # IMAP commands.  Any value that is valid for SequenceSet.new may be used
    # for these command arguments.  Some IMAP response data returns a
    # SequenceSet, for example ESearchResult or as the data for a
    # "MODIFIED" ResponseCode.
    #
    # SequenceSet.new takes a single optional argument, which may be an IMAP
    # formatted +sequence-set+ string or an enumeration of numbers and ranges.
    # Use ::[] with one or more arguments to return a normalized frozen
    # SequenceSet.
    #
    # SequenceSet.new with no arguments creates an empty sequence set.  But an
    # empty sequence set is invalid and cannot be created with ::[].
    #
    # === Using <tt>*</tt>
    #
    # IMAP sequence sets may contain a special value, <tt>*</tt>, which
    # represents the largest number in use.  From RFC9051:
    # >>>
    #   In the case of message sequence numbers, it is the number of messages
    #   in a non-empty mailbox.  In the case of unique identifiers, it is the
    #   unique identifier of the last message in the mailbox or, if the
    #   mailbox is empty, the mailbox's current UIDNEXT value.
    #
    # When creating a SequenceSet, <tt>*</tt> may be input as <tt>"*"</tt>,
    # <tt>:*</tt>, an endless range, or a range ending in <tt>-1</tt>.  It will
    # be converted into <tt>:*</tt> or an endless range.  For example:
    #
    #   Net::IMAP::SequenceSet["*"].to_a          # => [:*]
    #   Net::IMAP::SequenceSet["1234:*"].to_a     # => [1234..]
    #   Net::IMAP::SequenceSet[1234..-1].to_a     # => [1234..]
    #   Net::IMAP::SequenceSet[1234..].to_s       # => "1234:*"
    #   Net::IMAP::SequenceSet[1234..-1].to_s     # => "1234:*"
    #
    # Use #limit to convert <tt>*</tt> to a maximum value.  when a range
    # includes <tt>*</tt>, the maximum value will always be matched:
    #
    #   Net::IMAP::SequenceSet["9999:*"].limit(max: 25)
    #   # => Net::IMAP::SequenceSet["25"]
    class SequenceSet

      # maximum uint32 value
      MAX = 2**32 - 1
      private_constant :MAX

      # used to internally represent +"*"+.
      STAR = 2**32
      private_constant :STAR

      # <tt>nz-number / "*"</tt>.
      VALID = 1..STAR
      private_constant :VALID

      # Valid inputs for <tt>*</tt>: +:*+, <tt>"*"</tt>, or <tt>-1</tt>
      STARS = [:*, ?*, -1, 2**32].freeze
      private_constant :STARS

      ToSequenceSet = ->{_1.respond_to? :to_sequence_set}
      private_constant :ToSequenceSet

      class << self

        # Returns a frozen SequenceSet, constructed from +values+.
        #
        # An empty SequenceSet is invalid and will raise a DataFormatError.
        #
        # Use ::new to create a mutable or empty SequenceSet.
        def [](*values)
          seqset = new.merge(*values)
          seqset.validate
          seqset.freeze
        end

        # If +obj+ is a SequenceSet, returns +obj+.  If +obj+ responds_to
        # +to_sequence_set+, calls +obj.to_sequence_set+ and returns the result.
        # Otherwise returns +nil+.
        #
        # If +obj.to_sequence_set+ doesn't return a SequenceSet, an exception is
        # raised.
        def try_convert(obj)
          return obj if obj.is_a?(SequenceSet)
          return unless respond_to?(:to_sequence_set)
          obj = obj.to_sequence_set
          return obj if obj.is_a?(SequenceSet)
          raise DataFormatError, "invalid object returned from to_sequence_set"
        end

      end

      # Create a new SequenceSet object from +input, which may be another
      # SequenceSet, or it may be an IMAP +sequence-set+ string, a number, a
      # range, <tt>*</tt>, or an enumerable of these.
      #
      # Use ::[] to create a frozen (non-empty) SequenceSet.
      def initialize(input = nil) input ? replace(input) : clear end

      # Removes all elements and returns self.
      def clear; @tuples, @str = [], ""; self end

      # Replace the contents of the set with the contents of +other+ and returns
      # self.
      #
      # +other+ may be another SequenceSet, or it may be an IMAP +sequence-set+
      # string, a number, a range, <tt>*</tt>, or an enumerable of these.
      #
      # Returns self.
      def replace(other)
        case other = object_try_convert(other)
        when SequenceSet then initialize_dup(other)
        when String      then self.atom = other
        else                  clear << other
        end
        self
      end

      # Returns the IMAP string representation.  In the IMAP grammar,
      # +sequence-set+ is a subset of +atom+ which is a subset of +astring+.
      #
      # Raises a DataFormatError when the set is empty.  Use #to_s to return an
      # empty string without error.
      #
      # If the set was created from a single string, that string is returned
      # without calling #normalize.  When a new value is added to the set, the
      # atom string is automatically #normalized.
      def atom
        raise DataFormatError, "empty sequence-set" if empty?
        @str.clone
      end

      # Returns #atom.  In the IMAP grammar, +atom+ is a subset of +astring+.
      alias astring atom

      # Returns the value of #atom, or an empty string when the set is empty.
      def to_s; @str.clone end

      # Assigns a new string to #atom and resets #elements to match.
      #
      # Use #add or #merge to add a string to the existing set.
      def atom=(str)
        tuples = str_to_tuples str
        @tuples, @str = [], -str.to_str
        tuples_add tuples
        self
      end

      # Freezes and returns the set.
      def freeze
        return if frozen?
        @tuples.each(&:freeze).freeze
        @str = -@str
        super
      end

      # Returns true when the other SequenceSet represents the same message
      # identifiers.  Encoding difference—such as order, overlaps, or
      # duplicates—are ignored.
      #
      #   Net::IMAP::SequenceSet["1:3"]   == Net::IMAP::SequenceSet["1:3"]  # => true
      #   Net::IMAP::SequenceSet["1,2,3"] == Net::IMAP::SequenceSet["1:3"]  # => true
      #   Net::IMAP::SequenceSet["1,3"]   == Net::IMAP::SequenceSet["3,1"]  # => true
      #   Net::IMAP::SequenceSet["9,1:*"] == Net::IMAP::SequenceSet["1:*"]  # => true
      #
      # Related: #eql?, #normalize
      def ==(rhs)
        self.class == rhs.class && (to_s == rhs.to_s || tuples == rhs.tuples)
      end

      # Hash equality requires the same encoded #atom representation.
      #
      #   Net::IMAP::SequenceSet["1:3"]  .eql? Net::IMAP::SequenceSet["1:3"]  # => true
      #   Net::IMAP::SequenceSet["1,2,3"].eql? Net::IMAP::SequenceSet["1:3"]  # => false
      #   Net::IMAP::SequenceSet["1,3"]  .eql? Net::IMAP::SequenceSet["3,1"]  # => false
      #   Net::IMAP::SequenceSet["9,1:*"].eql? Net::IMAP::SequenceSet["1:*"]  # => false
      #
      # Related: #==, #normalize
      def eql?(other) self.class == other.class && atom == other.atom end

      # See #eql?
      def hash; [self.class. atom].hash end

      # Returns the result of #cover?  Returns +nil+ if #cover? raises a
      # StandardError exception.
      def ===(rhs)
        cover?(rhs)
      rescue
        nil
      end

      # Returns +true+ when +obj+ is in found within set, and +false+
      # otherwise.
      #
      # Returns +false+ unless +obj+ is an Integer, Range, Set,
      # +sequence-set+ String, SequenceSet, or <tt>:*</tt>.
      def cover?(obj)
        obj = object_try_convert(obj)
        case obj
        when VALID              then include?      obj
        when Range              then range_cover?  obj
        when SequenceSet        then seqset_cover? obj
        when ToSequenceSet      then seqset_cover? SequenceSet.try_convert obj
        when Set, Array, String then seqset_cover? SequenceSet.new         obj
        end
      end

      # Returns +true+ when +number+ is in +self+, and +false+ otherwise.
      # Returns +false+ unless +number+ is an Integer.
      #
      # Use #cover?, #===, or #subset? to check if a Range is covered or a Set
      # is a subset.
      def include?(number)
        return include_star? if STARS.include?(number)
        VALID.cover?(number) && range_gte_to(number)&.cover?(number)
      end

      # Returns +true+ when the set contains <tt>*</tt>.
      def include_star?; @tuples.last&.last == STAR end

      # :call-seq: max(star: :*) => Integer | star | nil
      #
      # Returns the maximum value in +self+, +star+ when the set includes
      # <tt>*</tt>, or +nil+ when the set is empty.
      def max(star: :*)
        (val = @tuples.last&.last) && val == STAR ? star : val
      end

      # :call-seq: min => Integer | nil
      #
      # Returns the minimum value in +self+, or +nil+ if empty.
      def min(star: :*)
        (val = @tuples.first&.first) && val == STAR ? star : val
      end

      # :call-seq: minmax(star: :*) => [Integer, Integer | star] | nil
      #
      # Returns a 2-element array containing the minimum and maximum numbers in
      # +self+, or +nil+ when the set is empty.
      def minmax(star: :*); [min(star: star), max(star: star)] unless empty? end

      # Returns a new sequence set that is the union of both sequence sets.
      #
      # Related: #add, #merge
      def +(rhs) dup.add rhs end
      alias :|    :+
      alias union :+

      # Returns a new sequence set built by duplicating this set and removing
      # every number that appears in the +rhs+ object.
      #
      # Related: #subtract
      def -(rhs) dup.subtract rhs end
      alias difference :-

      def &(rhs) self - SequenceSet.new(rhs).complement! end
      alias intersection :&

      def ^(rhs) (self | rhs).subtract(self & rhs) end
      alias xor :^

      # Adds a range, number, or string to the set and returns self.  The #atom
      # will be regenerated.  Use #merge to add many elements at once.
      def add(object)
        tuples_add input_to_tuples object
        normalize!
        self
      end
      alias << add

      # Adds the given object to the set and returns self.  If the object is
      # already in the set, returns nil.
      def add?(obj) add(obj) unless cover?(obj) end

      # Merges the elements in each object to the set and returns self.  The
      # #atom will be regenerated after all inputs have been merged.
      def merge(*inputs)
        tuples_add inputs.flat_map { input_to_tuples _1 }
        normalize!
        self
      end

      # Deletes every number that appears in +object+ and returns self.  +object
      # can be a range, a number, or an enumerable of ranges and numbers.  The
      # #atom will be regenerated.
      def subtract(object)
        tuples_subtract input_to_tuples object
        normalize!
        self
      end

      # Returns an array of ranges and integers.
      #
      # The returned elements are sorted and deduplicated, even when the input
      # #atom is not.  <tt>*</tt> will sort last.  See #normalize.
      #
      # By itself, <tt>*</tt> translates to <tt>:*</tt>.  A range containing
      # <tt>*</tt> translates to an endless range.  Use #limit to translate both
      # cases to a maximum value.
      #
      # If the original input was unordered or contains overlapping ranges, the
      # returned ranges will be ordered and coalesced.
      #
      #   Net::IMAP::SequenceSet["2,5:9,6,*,12:11"].elements
      #   # => [2, 5..9, 11..12, :*]
      #
      # Related: #ranges, #numbers
      def elements; each_element.to_a end

      # Yields each element in #elements to the block and returns self.
      #
      # Returns an enumerator when called without a block.
      def each_element
        return to_enum(__method__) unless block_given?
        @tuples.each { yield tuple_to_el(_1, _2) }
        self
      end

      # Returns an array of ranges
      #
      # The returned elements are sorted and deduplicated, even when the input
      # #atom is not.  <tt>*</tt> will sort last.  See #normalize.
      #
      # <tt>*</tt> translates to an endless range.  By itself, <tt>*</tt>
      # translates to <tt>:*..</tt>.  Use #limit to set <tt>*</tt> to a maximum
      # value.
      #
      # The returned ranges will be ordered and coalesced, even when the input
      # #atom is not.  <tt>*</tt> will sort last.  See #normalize.
      #
      #   Net::IMAP::SequenceSet["2,5:9,6,*,12:11"].ranges
      #   # => [2..2, 5..9, 11..12, :*..]
      #   Net::IMAP::SequenceSet["123,999:*,456:789"].ranges
      #   # => [123..123, 456..789, 999..]
      #
      # Related: #elements, #numbers, #to_set
      def ranges; each_range.to_a end

      # Yields each range in #ranges to the block and returns self.
      #
      # Returns an enumerator when called without a block.
      def each_range
        return to_enum(__method__) unless block_given?
        @tuples.each { yield tuple_to_range(_1, _2) }
        self
      end

      # Returns a sorted array of all of the number values in the sequence set.
      #
      # The returned numbers are sorted and deduplicated, even when the input
      # #atom is not.  <tt>*</tt> will sort last.  See #normalize.
      #
      #   Net::IMAP::SequenceSet["2,5:9,6,*,12:11"].numbers
      #   # => [2, 5, 6, 7, 8, 9, 11, 12, :*]
      #
      # By itself, <tt>*</tt> translates to <tt>:*</tt>.  If the set contains a
      # range with <tt>*</tt>, RangeError will be raised.  Enumerating all the
      # numbers up to <tt>2**32 - 1</tt> could return a _very_ large Array, with
      # over 4 billion numbers, requiring more than 34 GB of memory on a 64-bit
      # architecture.  Use #limit to set an upper bound.
      #
      #   Net::IMAP::SequenceSet["10000:*"].numbers
      #   # !> RangeError
      #
      # Related: #elements, #ranges, #to_set
      def numbers; @tuples.flat_map { el_to_nums tuple_to_el _1, _2 } end

      # Returns a Set with all of the #numbers in the sequence set.
      #
      # See #numbers for a description of how <tt>*</tt> is handled.
      #
      # Related: #elements, #ranges, #numbers
      def to_set; Set.new(numbers) end

      # Returns the count of #numbers in the set.
      #
      # If <tt>*</tt> and <tt>2**32 - 1</tt> (the maximum 32-bit unsigned
      # integer value) are both in the set, they will only be counted once.
      def count
        sum = @tuples.sum { _2 - _1 + 1 }
        include_star? && include?(MAX) ? sum - 1 : sum
      end

      # Returns a frozen SequenceSet with <tt>*</tt> converted to +max+, numbers
      # and ranges over +max+ removed, and ranges containing +max+ converted to
      # end at +max+.
      #
      # Use #limit to set the largest number in use before enumerating.  See the
      # warning on #numbers.
      #
      #   Net::IMAP::SequenceSet["5,10:500,999"].limit(max: 37)
      #   # => Net::IMAP::SequenceSet["5,10:37"]
      #
      # <tt>*</tt> is always interpreted as the maximum value.  When the set
      # contains star, it will be set equal to the limit.
      #
      #   Net::IMAP::SequenceSet["*"].limit(max: 37)
      #   # => Net::IMAP::SequenceSet["37"]
      #   Net::IMAP::SequenceSet["5:*"].limit(max: 37)
      #   # => Net::IMAP::SequenceSet["5:37"]
      #   Net::IMAP::SequenceSet["500:*"].limit(max: 37)
      #   # => Net::IMAP::SequenceSet["37"]
      #
      # Returns +nil+ when all members are excluded, not an empty SequenceSet.
      #
      #   Net::IMAP::SequenceSet["500:999"].limit(max: 37) # => nil
      #
      # When the set is frozen and the result would be unchanged, +self+ is
      # returned.
      def limit(max:)
        max = valid_int(max)
        if    empty?                      then nil
        elsif !include_star? && max < min then nil
        elsif max(star: STAR) <= max      then frozen? ? self : dup.freeze
        else                                   dup.limit!(max: max).freeze
        end
      end

      # Removes all members over +max+ an returns self.  If <tt>*</tt> is a
      # member, it will be converted to +max+.
      #
      # Related: #limit
      def limit!(max:)
        star = include_star?
        # TODO: subtract(max..)
        if (over_range, idx = tuple_gte_with_index(max + 1))
          if over_range.first <= max
            over_range[1] = max
            idx += 1
          end
          tuples.slice!(idx..)
        end
        star and add max
        self
      end

      # Returns true if the set contains no elements
      def empty?; @tuples.empty? end

      # Returns true if the set contains every possible element.
      def full?; @tuples == [[1, STAR]] end

      # Returns the complement of self, a SequenceSet which contains all numbers
      # _except_ for those in this set.
      def complement; dup.complement! end
      alias ~ complement

      # Converts the SequenceSet to its own #complement.  It will contain all
      # possible values _except_ for those currently in the set.
      def complement!
        return replace(VALID) if empty?
        return clear          if full?
        @tuples = @tuples.flat_map { [_1 - 1, _2 + 1] }.tap do
          if _1.first < 1       then _1.shift else _1.unshift 1 end
          if STAR     < _1.last then _1.pop   else _1.push STAR end
        end.each_slice(2).to_a
        normalize!
        self
      end

      # Returns a new SequenceSet with a normalized string representation.
      #
      # The returned set's #atom string are sorted and deduplicated.  Adjacent
      # or overlapping elements will be merged into a single larger range.
      #
      #   Net::IMAP::SequenceSet["1:5,3:7,10:9,10:11"]
      #   # => Net::IMAP::SequenceSet["1:7,9:11"]
      def normalize; dup.normalize! end

      # Sorts, deduplicates, and merges the #atom string, as appropriate
      def normalize!; @str = @tuples.map { tuple_to_str _1 }.join(",") end

      def inspect
        if frozen?
          "%s[%p]" % [self.class, to_s]
        else
          "#<%s %s>" % [self.class, empty? ? "empty" : to_s.inspect]
        end
      end

      # Returns self
      alias to_sequence_set itself

      # Unstable API, for internal use only (Net::IMAP#validate_data)
      def validate # :nodoc:
        empty? and raise DataFormatError, "empty sequence-set is invalid"
        validate_tuples # validated during input; only raises when there's a bug
        true
      end

      # Unstable API, for internal use only (Net::IMAP#send_data)
      def send_data(imap, tag) # :nodoc:
        imap.__send__(:put_string, atom)
      end

      protected

      attr_reader :tuples

      private

      # frozen clones are shallow copied
      def initialize_clone(other)
        if other.frozen? then super else initialize_dup(other) end
      end

      def initialize_dup(other)
        @tuples = other.tuples.map(&:dup)
        @str    = -other.to_s
        super
      end

      def merging(normalize: true)
        yield
        normalize! if normalize
        self
      end

      # For YAML serialization
      def encode_with(coder) # :nodoc:
        # we can reconstruct from the string
        coder['atom'] = to_s
      end

      # For YAML deserialization
      def init_with(coder) # :nodoc:
        @tuples = []
        self.atom = coder['atom']
      end

      def input_to_tuples(obj)
        object_to_tuples(obj) ||
          obj.respond_to?(:each) && enum_to_tuples(obj) or
          raise DataFormatError, "expected nz-number, range, string, or enum"
      end

      def enum_to_tuples(enum)
        raise DataFormatError, "invalid empty enum" if enum.empty?
        enum.flat_map do
          object_to_tuples(_1) or
            raise DataFormatError, "expected nz-number, range, or string"
        end
      end

      def object_try_convert(input)
        SequenceSet.try_convert(input) ||
          STARS.include?(input) && STAR ||
          # Integer.try_convert(input) || # ruby 3.1+
          input.respond_to?(:to_int) && Integer(input.to_int) ||
          String.try_convert(input) ||
          input
      end

      def object_to_tuples(obj)
        obj = object_try_convert obj
        case obj
        when VALID       then [[obj, obj]]
        when Range       then [range_to_tuple(obj)]
        when String      then str_to_tuples obj
        when SequenceSet then obj.tuples
        else
        end
      end

      def el_to_nums(e) e.is_a?(Range) ? e.to_a : e end

      def valid_int(obj)
        VALID.cover?(obj) ? obj : STARS.include?(obj) ? STAR : nz_number(obj)
      end

      def range_cover?(rng)
        rmin, rmax = range_to_tuple(rng)
        VALID.cover?(rmin) && VALID.cover?(rmax) &&
          range_gte_to(rmin)&.cover?(rmin..rmax)
      end

      def range_to_tuple(range)
        first, last = [range.begin || 1, range.end || STAR]
          .map! { valid_int _1 }
        last -= 1 if range.exclude_end?
        unless first <= last
          raise DataFormatError, "invalid range for sequence-set: %p" % [range]
        end
        [first, last]
      end

      def seqset_cover?(seqset)
        (min..max(star: nil)).cover?(seqset.min..seqset.max(star: nil)) &&
          seqset.elements.all? {|e| cover? e }
      end

      def str_to_num(str) str == "*" ? STAR : nz_number(str) end

      def str_to_tuples(string)
        string.to_str
          .split(",")
          .tap { _1.empty? and raise DataFormatError, "invalid empty string" }
          .map! {|str| str.split(":", 2).compact.map! { str_to_num _1 }.minmax }
      end

      def tuple_to_el(a, b) a==STAR ? :* : b==STAR ? (a..) : a==b ? a : a..b end
      def tuple_to_range(a, b) b != STAR ? a..b : a != STAR ? a.. : :*.. end
      def tuple_to_str(tuple) tuple.uniq.map{_1 == STAR ? "*" : _1}.join(":") end

      def tuples_add(tuples) tuples.each do tuple_add _1 end end
      def tuples_subtract(tuples) tuples.each do tuple_subtract _1 end end

      def tuple_add(tuple)
        first, last    = tuple
        first_adjacent = first - 1
        last_adjacent  = last  + 1
        lower, lower_idx = tuple_gte_with_index(first_adjacent)
        if lower.nil?
          # ---|=============|  nothing follows
          #                       |=====tuple========|
          tuples << tuple
        elsif last_adjacent < lower.first
          # -------------------------|====lower====|----
          #         |====tuple====|
          tuples.insert(lower_idx, tuple)
        else
          # ------?????=====lower=====?????----
          #         |======tuple========|
          if first < lower.first
            # ------------|====lower====????----
            #         |====tuple=========|
            lower[0] = first
          end
          if lower.last < last
            # ---?????=====lower=====?????
            #       |======tuple======|
            upper, upper_idx = tuple_gte_with_index(last_adjacent)
            if upper.nil?
              # ----????====lower====|----|====|    nothing follows
              #       |===========tuple==============|
            elsif (last_adjacent) < upper.first
              # ----????====lower====|----|====|-------|====upper====|----
              #       |===============tuple========|
              upper_idx -= 1
            else
              # ----????====lower====|----|====|----|====upper====|-----
              #       |===============tuple============|
              last = upper.last
            end
            lower[1] = last
            tuples.slice!(lower_idx + 1 .. upper_idx)
          end
        end
      end

      #         |====tuple================|
      # --|====|                               no more       1. noop
      # --|====|---------------------------|====lower====|-- 2. noop
      # -------|======lower================|---------------- 3. split
      # --------|=====lower================|---------------- 4. trim beginning
      #
      # -------|======lower====????????????----------------- trim lower
      # --------|=====lower====????????????----------------- delete lower
      #
      # -------??=====lower===============|----------------- 5. trim/delete one
      # -------??=====lower====|--|====|       no more       6. delete rest
      # -------??=====lower====|--|====|---|====upper====|-- 7. delete until
      # -------??=====lower====|--|====|--|=====upper====|-- 8. delete and trim
      def tuple_subtract(tuple)
        first, last = tuple
        lower, lower_idx = tuple_gte_with_index(first)
        return if lower.nil?          # case 1
        lower_first, lower_last = lower
        return if last < lower_first  # case 2

        if last < lower_last          # cases 3 and 4
          lower[0] = last + 1
          if lower_first < first      # case 3
            tuples.insert(lower_idx, [lower_first, first - 1])
          end

        else
          if lower_first < first # trim lower (else delete lower)
            lower[1] = first - 1
            lower_idx += 1
          end
          if last == lower_last                           # case 5
            upper, upper_idx = lower, lower_idx
          elsif (upper, upper_idx = tuple_gte_with_index(last + 1))
            upper_idx -= 1                                # cases 7 and 8
            upper[0] = last + 1 if upper.first <= last    # case 8 (else case 7)
          end

          tuples.slice!(lower_idx..upper_idx)
        end
      end

      def tuple_gte_with_index(num)
        idx = tuples.bsearch_index { _2 >= num } and [tuples[idx], idx]
      end

      def range_gte_to(num)
        first, last = tuples.bsearch { _2 >= num }
        first..last if first
      end

      def validate_tuples
        tuples.each do validate_tuple _1 end
        tuples.each_cons(2) do |a, b|
          unless (a.last + 1) < b.first
            raise DataFormatError, "sequence-set failed to merge %p and %p" % [
              a, b,
            ]
          end
        end
      end

      def validate_tuple(tuple)
        min, max = tuple
        unless VALID.cover?(min) && VALID.cover?(max) && min <= max
          raise DataFormatError, "invalid sequence-set range: %p" % [tuple]
        end
      end

      def nz_number(num)
        String === num && !/\A[1-9]\d*\z/.match?(num) and
          raise DataFormatError, "%p is not a valid nz-number" % [num]
        NumValidator.ensure_nz_number Integer num
      end

    end
  end
end
