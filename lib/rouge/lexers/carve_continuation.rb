# -*- coding: utf-8 -*- #
# frozen_string_literal: true

module Rouge
  module Lexers
    # Decides which `+` characters of a Carve document are continuation
    # markers (Part 9 §17 L3, CARVE-P9-031). The marker is relative: it sits at
    # an open container's marker column, so the answer needs the container
    # stack the line-based lexer states do not carry. This pass walks the
    # document once and returns the character offsets of the markers.
    #
    # It is a reduced block model: list items, quotes, footnotes, definitions
    # and fences, with lazy paragraph lines. Shapes it cannot place (tables,
    # divs, attribute blocks) read as text.
    class CarveContinuation
      TAB = 4
      ORDERED = /\A(?:\d+|[A-Za-z]|[ivxlcdm]+|[IVXLCDM]+)[.)]/.freeze
      BULLET = /\A[-*](?=[ \t]|\z)/.freeze
      FENCE = /\A(`{3,}|~{3,})/.freeze

      Container = Struct.new(:kind, :col, :content, :quotes, keyword_init: true)

      # A line whose only content after quote prefixes and openers is `+`:
      # the shapes where the `+` is a marker or a refused marker.
      CANDIDATE = /
        \A(?:[ \t]|>|(?:[-*]|(?:\d+|[A-Za-z]|[ivxlcdm]+|[IVXLCDM]+)[.)])(?:\{[^}\n]*\})?(?=[ \t])
        |\[[^\]\n]\](?=[ \t])|::?(?=[ \t])|\[\^[^\]\n]+\]:(?=[ ]))*\+[ \t]*\r?\z
      /x.freeze

      def self.markers(source)
        new(source).markers
      end

      # Offsets of every `+` that stands where a marker could.
      def self.candidates(source)
        offset = 0
        source.split("\n", -1).each_with_object([]) do |line, found|
          found << offset + line.rindex('+') if line.match?(CANDIDATE)
          offset += line.length + 1
        end
      end

      def initialize(source)
        @lines = source.split("\n", -1)
        @markers = []
      end

      def markers
        stack = []
        fence = nil
        para = nil
        force = 0
        offset = 0
        @lines.each_with_index do |raw, index|
          line = raw.chomp("\r")
          cols = columns(line)
          matched, pos, quotes = match(stack, line, cols, force)
          rest = line[pos..] || ''

          if fence && (fence[:forced] || matched >= fence[:depth])
            fence = nil if rest.match?(/\A[ \t]*#{Regexp.escape(fence[:char])}{#{fence[:width]},}[ \t]*\z/)
            offset += raw.length + 1
            force = 0
            next
          end
          fence = nil

          lone = rest.match(/\A([ \t]*)\+[ \t]*\z/)
          attached = 0
          if rest.match?(/\A[ \t]*\z/)
            # a blank line ends every quote it does not prefix
            stack.slice!(matched..)
            para = nil
          elsif lone
            col = cols[pos + lone[1].length]
            target = stack.rindex { |c| c.col == col && c.quotes == quotes && c.kind != :term }
            if target && follower?(index + 1, quotes, col)
              @markers << offset + pos + lone[1].length
              stack.slice!((target + 1)..)
              attached = stack.length
              para = nil
            else
              stack.slice!(matched..) unless para
              para ||= stack.length
            end
          elsif para && (!opener?(rest) || lazy_list?(stack, rest, quotes) || unclosed_fence?(rest, index))
            # a lazy line keeps every container open
          else
            stack.slice!(matched..)
            para, fence, plus = open_blocks(stack, line, cols, pos, quotes, para, index)
            fence[:forced] = true if fence && force.positive?
            if plus
              @markers << offset + plus
              attached = stack.length
            end
          end
          force = attached
          offset += raw.length + 1
        end
        @markers
      end

      private

      # The visual column of every character position, tabs expanded.
      def columns(line)
        cols = []
        col = 0
        line.each_char do |ch|
          cols << col
          col = ch == "\t" ? (col / TAB + 1) * TAB : col + 1
        end
        cols << col
        cols
      end

      # How many containers the line continues, where its content starts, and
      # how many quote prefixes it passed.
      # The containers up to +force+ are the ones an attached line enters.
      def match(stack, line, cols, force)
        pos = 0
        quotes = 0
        matched = 0
        stack.each do |c|
          blank = line[pos..].to_s.match?(/\A[ \t]*\z/)
          if c.kind == :quote
            ws = line[pos..][/\A[ \t]*/]
            unless line[pos + ws.length] == '>' && (line[pos + ws.length + 1].nil? || line[pos + ws.length + 1].match?(/[ \t]/))
              break unless matched < force

              matched += 1
              next
            end

            pos += ws.length + 1
            pos += 1 if line[pos]&.match?(/[ \t]/)
            quotes += 1
          elsif blank
            # a blank line keeps an item open
          else
            ws = line[pos..][/\A[ \t]*/]
            if cols[pos + ws.length] >= c.content || matched < force
              pos = advance(line, cols, pos, c.content)
            else
              break
            end
          end
          matched += 1
        end
        [matched, pos, quotes]
      end

      # Move +pos+ over whitespace up to +col+.
      def advance(line, cols, pos, col)
        pos += 1 while line[pos]&.match?(/[ \t]/) && cols[pos + 1] <= col
        pos
      end

      def opener?(rest)
        text = rest.lstrip
        text.match?(BULLET) || text.match?(ORDERED) && text.match?(/\A\S+[ \t]/) ||
          text.start_with?('>') || text.match?(FENCE) || text.match?(/\A(?:\#{1,6}[ \t]|:::|::?[ \t]|\[\^[^\]]+\]:[ ])/)
      end

      # A list marker cannot interrupt a paragraph unless it continues a list
      # already open in the line's own quote context.
      def lazy_list?(stack, rest, quotes)
        text = rest.lstrip
        return false unless list_marker?(text)

        stack.none? { |c| c.kind == :item && c.quotes == quotes }
      end

      # Only a closed fence interrupts a paragraph.
      def unclosed_fence?(rest, index)
        f = rest.lstrip.match(FENCE)
        return false unless f

        @last_closer ||= {}
        last = @last_closer[f[1]] ||= begin
          closer = /\A[ \t>]*#{Regexp.escape(f[1][0])}{#{f[1].length},}[ \t]*\r?\z/
          @lines.rindex { |l| l.match?(closer) } || -1
        end
        last <= index
      end

      def list_marker?(text)
        text.match?(BULLET) || text.match?(/#{ORDERED.source}(?=[ \t]|\z)/)
      end

      # The block a line at +col+ opens is the one the marker attaches.
      def follower?(index, quotes, col)
        line = @lines[index]
        return false if line.nil?

        line = line.chomp("\r")
        cols = columns(line)
        pos = 0
        quotes.times do
          ws = line[pos..][/\A[ \t]*/]
          return false unless line[pos + ws.length] == '>'

          pos += ws.length + 1
          pos += 1 if line[pos]&.match?(/[ \t]/)
        end
        ws = line[pos..][/\A[ \t]*/]
        text = line[(pos + ws.length)..]
        return false if text.nil? || text.empty?
        return false unless cols[pos + ws.length] == col

        !list_marker?(text)
      end

      # Push the containers a line opens. Returns the paragraph depth, an open
      # fence and the offset of a first-block marker.
      def open_blocks(stack, line, cols, pos, quotes, para, index)
        base = pos
        first = true
        last = nil
        loop do
          ws = line[pos..][/\A[ \t]*/]
          at = pos + ws.length
          text = line[at..]
          col = cols[at]
          # `>+` and `>>+` open quotes too: a glued `>` run counts when the
          # line ends in the marker.
          if text.start_with?('>') && (text[1].nil? || text[1] == ' ' || text.match?(/\A>[> ]*\+[ \t]*\z/))
            break if first && at != base

            stack << Container.new(kind: :quote, col: col, content: col + 2, quotes: quotes)
            quotes += 1
            pos = at + 1
            pos += 1 if line[pos] == ' '
            last = :quote
          elsif (m = text.match(/\A(?:[-*]|#{ORDERED.source})(?:\{[^}\n]*\})?(?= |\z)/))
            
            after = at + m[0].length
            gap = line[after..][/\A[ \t]*/]
            content = gap.empty? || cols[after + gap.length] - cols[after] > 4 ? cols[after] + 1 : cols[after + gap.length]
            stack << Container.new(kind: :item, col: col, content: content, quotes: quotes)
            pos = after + gap.length
            last = m[0].start_with?('-', '*') ? :bullet : :ordered
          elsif last == :bullet && (m = text.match(/\A\[[^\]\n]\](?= )/))
            pos = at + m[0].length
            pos += line[pos..][/\A[ \t]*/].length
            last = :task
          elsif (first || last == :quote) && text.match?(/\A\[\^[^\]\n]+\]: /)
            m = text.match(/\A\[\^[^\]\n]+\]: /)
            stack << Container.new(kind: :note, col: col, content: col + 2, quotes: quotes)
            pos = at + m[0].length
            last = :note
          elsif (first || last == :quote) && text.match?(/\A:: /)
            @term_open = stack.length
            stack << Container.new(kind: :term, col: col, content: col + 2, quotes: quotes)
            return [nil, nil, nil]
          elsif (first || last == :quote) && @term_open == stack.length && text.match?(/\A: /)
            stack << Container.new(kind: :definition, col: col, content: col + 2, quotes: quotes)
            pos = at + 2
            last = :definition
          else
            break
          end
          first = false
        end

        ws = line[pos..][/\A[ \t]*/]
        text = line[(pos + ws.length)..] || ''
        @term_open = last == :definition ? stack.length - 1 : nil
        if last && text.match?(/\A\+[ \t]*\z/)
          case last
          when :quote
            return [nil, nil, pos] if ws.empty? && first_block_follower?(index + 1, stack, cols[base])
          when :note
            return [nil, nil, pos + ws.length] if first_block_follower?(index + 1, stack, cols[base], lists: true)
          else
            return [nil, nil, pos + ws.length]
          end
        end
        return [nil, nil, nil] if text.empty?

        # at document level a fence opens at column 0 only
        if (f = text.match(FENCE)) && (stack.any? || ws.empty? || pos != base)
          return [nil, { char: f[1][0], width: f[1].length, depth: stack.length }, nil]
        end

        [stack.length, nil, nil]
      end

      # A first-block marker after a quote or a footnote attaches a non-list
      # block at document column 0 or at the column where the line's openers
      # began; right after an enclosing quote's prefix counts as column 0 of
      # that quote. A line that re-enters the opened container is its text.
      def first_block_follower?(index, stack, base_col, lists: false)
        line = @lines[index]
        return false if line.nil?

        line = line.chomp("\r")
        cols = columns(line)
        pos = 0
        reached = 0
        after_quote = true
        stack.each do |c|
          ws = line[pos..][/\A[ \t]*/]
          at = pos + ws.length
          if c.kind == :quote
            break unless line[at] == '>' && (line[at + 1].nil? || line[at + 1] == ' ')

            pos = at + 1
            pos += 1 if line[pos] == ' '
            after_quote = true
          else
            break unless line[at] && cols[at] >= c.content

            pos = advance(line, cols, pos, c.content)
            after_quote = false
          end
          reached += 1
        end
        return false if reached == stack.length

        ws = line[pos..][/\A[ \t]*/]
        at = pos + ws.length
        text = line[at..] || ''
        return false if text.empty? || (!lists && list_marker?(text))

        return cols[at].zero? || cols[at] == stack.last.col if reached.zero?

        cols[at] == base_col || (after_quote && ws.empty?)
      end
    end
  end
end
