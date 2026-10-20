# -*- coding: utf-8 -*- #
# frozen_string_literal: true

require_relative 'carve_continuation'

module Rouge
  module Lexers
    # Carve is a lightweight markup language for documents and the web. Its
    # inline
    # delimiters deliberately differ from Markdown's, which is why lexing a
    # Carve document as Markdown produces actively WRONG output rather than
    # merely plain text:
    #
    #   Carve        means            Markdown would read it as
    #   ---------    -------------    -------------------------
    #   *bold*       strong           emphasis
    #   /italic/     emphasis         literal slashes
    #   _under_      underline        emphasis
    #   ~strike~     strikethrough    subscript / literal
    #   {=mark=}     highlight        literal braces
    #   {^sup^}      superscript      literal braces
    #
    # WHY THE BLOCK OPENERS ARE NOT ANCHORED AT COLUMN 0. Carve opens a block at
    # column 0, or at an enclosing container's content column - nowhere in
    # between. So `  # H` at document level is a paragraph, while the same
    # opener at a list item's content column is a real heading. Telling those
    # apart needs a container model that tracks the item's content column. A
    # regex lexer's state stack could carry one, but the sibling grammars
    # (Prism, highlight.js, Pygments) do not, and this lexer keeps their
    # trade-off on purpose so they agree: block openers match at any indent and
    # knowingly over-colour the rare indented-at-document-level case, rather
    # than under-colouring the common valid shape of an indented construct
    # inside a list item.
    #
    # WHY AN ATTRIBUTE BLOCK IS ONE TOKEN. `{#id .cls key="v" :lang}` is emitted
    # whole as Name::Attribute rather than split into id, class, key, value and
    # language parts. Splitting reads better in isolation, but an attribute
    # block can carry a brace inside a quoted value, a language tag, and a bare
    # key that is not an attribute at all, and the sibling grammars treat the
    # block as one unit; a consumer asking "is this text inside an attribute
    # block" must get the same answer here as it does there.
    #
    # WHERE ROUGE CANNOT SAY WHAT CARVE MEANS. Carve's `_x_` is UNDERLINE, not
    # emphasis, and Rouge has no underline token - the vocabulary stops at
    # Generic::Emph, Generic::Strong and Generic::EmphStrong. The content takes
    # Generic::Emph so it is at least marked up, and the delimiters stay
    # Punctuation so a consumer can still tell underline from italic by the
    # delimiter it carries. Pygments, which has Generic.Underline, does make
    # the distinction.
    #
    # Spec: https://markup-carve.github.io/carve/
    class Carve < RegexLexer
      class DelimitedTable < RegexLexer
        # Unquoted fields are Name::Variable (colored in the default Rouge
        # styles, unlike a bare Name); the header record's unquoted fields are
        # Name::Attribute.
        start { @header = true }

        def field_token
          @header ? Name::Attribute : Name::Variable
        end

        state :root do
          rule /"/ do
            token Str
            push :unquoted
            push :quoted
          end
          rule /[,\t]/ do |m|
            if m[0] == self.class::SEPARATOR
              token Keyword
            else
              token field_token
              push :unquoted
            end
          end
          rule /[^,\t\n]+/ do
            token field_token
            push :unquoted
          end
          rule /\n/ do
            token Text
            @header = false
          end
        end

        state :unquoted do
          rule /[,\t]/ do |m|
            if m[0] == self.class::SEPARATOR
              token Keyword
              pop!
            else
              token field_token
            end
          end
          rule /[^,\t\n]+/ do
            token field_token
          end
          rule /\n/ do
            token Text
            @header = false
            pop!
          end
        end

        state :quoted do
          rule /""/, Str::Escape
          rule /"/, Str, :pop!
          rule /[^"]+/, Str
        end
      end

      class CsvTable < DelimitedTable
        SEPARATOR = ','.freeze
      end

      class TsvTable < DelimitedTable
        SEPARATOR = "\t".freeze
      end

      title 'Carve'
      desc 'Carve, a lightweight markup language for documents and the web'

      tag 'carve'
      aliases 'crv'
      filenames '*.crv', '*.carve'
      mimetypes 'text/x-carve'

      # A leading margin. A byte order mark at the start of a document is not
      # content, so a block opener behind one is still a block opener.
      MARGIN = /[ \t﻿]*/.freeze

      # One attribute block, brace to brace. Quoted values may contain a brace
      # and an escaped quote, so the value alternatives come before the
      # bare-character one; a single nested brace pair is allowed for a braced
      # span written inside. The tail is the block after its `{`.
      ATTRS_TAIL = %r/
        (?=[.:}'"]|\#[\w-]+[\s}]|[A-Za-z][\w-]*(?:[=\s}]|$))(?:
          "(?:[^"\\\n]|\\.)*"
          |'(?:[^'\\\n]|\\.)*'
          |\{[^{}\n]*\}
          |[^{}\n]
        )*\}
      /x.freeze
      ATTRS = /\{#{ATTRS_TAIL}/.freeze

      # The same block as a STANDALONE ATTRIBUTE LINE, which may span lines
      # but not a blank one: a blank line ends the block it would attach to.
      # The inline form cannot span lines at all, because an unclosed inline
      # `{` would otherwise swallow the rest of the document.
      LINE_BREAK = '\n(?![ \t]*(?:\n|\z))'
      ATTRS_LINE = %r/
        \{(?=[.:}'"]|\#[\w-]+[\s}]|[A-Za-z][\w-]*(?:[=\s}]|$))(?:
          "(?:[^"\\\n]|\\.|#{LINE_BREAK})*"
          |'(?:[^'\\\n]|\\.|#{LINE_BREAK})*'
          |\{(?:[^{}\n]|#{LINE_BREAK})*\}
          |[^{}\n]
          |#{LINE_BREAK}
        )*\}
      /x.freeze

      # The prefix of a line inside a blockquote, nested markers included.
      # Each `>` needs a space or the line end after it: `>foo` and `>> x`
      # are paragraph text.
      QUOTE_PREFIX = /(?:[ \t]*>(?=[ \t]|$))+[ \t]?/.freeze

      # A bracketed label that may itself contain three levels of brackets. A
      # regex cannot match arbitrarily balanced brackets, and a link label in
      # practice nests a level or two (`[t[z]](/u)`). Bounding the nesting keeps
      # the common shapes matching instead of stopping at the first inner
      # bracket, which is what a naive \[[^\]]*\] does.
      LABEL = begin
        inner = '[^\[\]\\\\\n]|\\\\.'
        pattern = "(?:#{inner})*"
        3.times { pattern = "(?:#{inner}|\\[#{pattern}\\])*" }
        Regexp.new("\\[#{pattern}\\]").freeze
      end

      # An ordered marker: a number, one letter, or a roman numeral. `Body.`
      # is a word, not a marker.
      ORDERED = '(?:\\d+|[A-Za-z]|[ivxlcdm]+|[IVXLCDM]+)[.)]'

      # The states read a column-0 `+` with a flush-left block below as an
      # attachment. Whether a `+` is the marker is settled by CarveContinuation.
      PLUS_NEXT = /(?=\n[^ \t\n])/.freeze

      # A list marker at the start of a line, as the list rules below read it.
      LIST_MARKER = "(?:[-*]|#{ORDERED}|\\.)(?:#{ATTRS})?(?:[ \\t]|$)"
      OPENER_RUN = "(?:(?:[-*]|#{ORDERED}|\\.)(?:#{ATTRS})? +[ \\t]*|> )+"

      # A table row needs its closing pipe: `| not a table` is a paragraph.
      ROW_END = /(?=(?:\\.|[^\\\n])*\|[ \t]*(?:#{ATTRS})?[ \t]*$)/.freeze

      # The block openers that interrupt a paragraph. A list marker and a
      # caption do not, and a fence does only when it is closed - that one is
      # checked in code, see the :paraline state.
      INTERRUPT = %r/
        \#{1,6}[ \t] | >(?:[ \t]|$) | ::: | ::[ \t] | %%
        | (?:(?:\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,})$
        | \|=?[<>^v~]*#{ROW_END}
        | (?:\[\^|\*\[|\[)[^\]\n]+\]:[ ]
        | #{ATTRS_LINE}[ \t]*$
      /x.freeze

      # Where a bracketed inline body must close, by the block it sits in: a
      # paragraph ends at a blank line or an interrupting block, a list item
      # also at the next marker, and a heading or table row at its line end.
      # A fence ends either only when it is closed, which is checked in code.
      BODY_ENDS = {
        para: /\n(?=[ \t]*(?:\n|\z)|#{MARGIN}(?:#{INTERRUPT}))/,
        item: /\n(?=[ \t]*(?:\n|\z)|#{MARGIN}(?:#{INTERRUPT}|#{LIST_MARKER}|:[ \t]))/,
        line: /\n/
      }.freeze
      FENCE_NEXT = /\n(?=#{MARGIN}(`{3,}|~{3,}))/.freeze

      # The block states that decide which of those ends applies.
      BODY_SCOPE = {
        paragraph: :para, listitem: :item, dlterm: :item, heading: :line,
        caption: :line, quoteline: :line, tablerow: :line, defline: :line
      }.freeze

      # A paragraph that is a lone image or display math: a caption under it
      # is that block's.
      IMAGE_LINE = %r/
        #{MARGIN}(?:!#{LABEL}(?:\([^)\n]*\)|#{LABEL})?|\$\$(`+)[^\n]*?\1)(?:#{ATTRS})?[ \t]*$
      /x.freeze

      # The braced inline families: delimiter, content token, state.
      BRACED = {
        '*' => [Generic::Strong, :forcedstrong], '/' => [Generic::Emph, :forcedemph],
        '_' => [Generic::Emph, :forcedunderline], '^' => [Generic::Emph, :superscript],
        ',' => [Generic::Emph, :subscript], '=' => [Generic::Inserted, :bracedmark],
        '+' => [Generic::Inserted, :insertion], '-' => [Generic::Deleted, :deletion]
      }.freeze

      # The bare emphasis delimiters: state, content token, and the characters
      # that may not stand before an opener or after it. A closer needs a
      # non-space before it and no letter or digit after it.
      BARE = {
        '*' => [:strong, Generic::Strong, /[\w*]/, /[\s*]/],
        '/' => [:emph, Generic::Emph, /[\w\/]/, /[\s\/]/],
        '_' => [:underline, Generic::Emph, /[\w_\/]/, /[\s_]/],
        '~' => [:strike, Generic::Deleted, /[\w~]/, /[\s~]/],
        '=' => [:mark, Generic::Inserted, /[\w=<>!]/, /[\s>=]/]
      }.freeze

      # Characters that can begin an inline construct. A run of anything else is
      # ordinary content and is emitted as ONE token - without this every
      # content character becomes its own token, which is both noisy and
      # unusable to a consumer asking whether a phrase carries a scope.
      INLINE_STARTERS = '\\\\%!`${\\[\\^<:@\\#*\\/_~=.\\-'

      # A run of content characters, excluding +extra+ as well.
      def self.plain_run(extra = '')
        Regexp.new("[^\n#{INLINE_STARTERS}#{extra}]+")
      end

      PLAIN = plain_run.freeze
      PLAIN_NO_PIPE = plain_run('|').freeze
      PLAIN_NO_BRACKET = plain_run('\\]').freeze

      state :root do
        mixin :block
      end

      # ------------------------------------------------------------------
      # Block level
      # ------------------------------------------------------------------

      # The openers a blockquote marker can introduce as well as a line start.
      # They are written once and instantiated twice: anchored at a line start
      # for the document, and unanchored for the rest of a line after `>`,
      # where the scanner already sits where the block would begin. Each one
      # enters its state through #open_block, which knows which of the two it
      # is running in.
      def self.block_openers(bol)
        root_margin = bol == '^' ? '()' : '( )'
        proc do
          # A raw block: the `=FORMAT` info string routes the payload to that
          # output format verbatim. Emitted as one token including the `=`,
          # because the format word without its sigil is not the construct.
          # The payload is never a language, so it is never delegated.
          rule %r/#{bol}(#{MARGIN})(`{3,}|~{3,})([ \t]*)(=[a-zA-Z][\w+.-]*)([^\n]*)/ do |m|
            groups Text, Punctuation, Text, Keyword::Type
            token Text, m[5]
            push_fence(m[2], nil)
          end

          # A code fence. The first word of the info string names a language,
          # and a lexer for it highlights the payload - the one place this
          # lexer looks past Carve, because a reader of a `.crv` file expects
          # an embedded PHP sample to look like PHP.
          rule %r/#{bol}(#{MARGIN})(`{3,}|~{3,})([ \t]*)([a-zA-Z][\w+#.-]*)?([^\n]*)/ do |m|
            groups Text, Punctuation, Text, Name::Builtin
            lex_info_string(m[5])
            push_fence(m[2], m[4])
          end

          # Container divs. A reserved kind word (note, tip, figure, ...)
          # names a known container; `:::` followed by `|` is the layout form.
          rule %r/#{bol}(#{MARGIN})(:{3,})([ \t]*)(\|)/ do
            groups Text, Punctuation, Text, Operator
            open_block
          end
          rule %r/#{bol}(#{MARGIN})(:{3,})([ \t]*)([a-zA-Z][\w-]*)?([^\n]*)/ do |m|
            groups Text, Punctuation, Text, Keyword::Namespace
            lex_info_string(m[5])
            open_block
          end

          # A caption line attaches to the block above or below it.
          rule %r/#{bol}(#{MARGIN})(\^)( +)(?=[ \t]*[^ \t\n])/ do
            groups Text, Punctuation, Text
            open_block :caption
          end

          # Headings. Carve has no setext form, so a `#` run is the only
          # spelling and a trailing `{...}` is NOT an attribute block here.
          rule %r/#{bol}(#{MARGIN})(\#{1,6})( +)(?=[ \t]*[^ \t\n])/ do
            groups Text, Punctuation, Text
            open_block :heading
          end

          # Thematic breaks, before the list rules so `---` is not a bullet.
          rule %r/#{bol}#{MARGIN}(?:(?:\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,})$/ do
            token Punctuation
            open_block
          end

          # Definition markers: footnote, link reference, abbreviation. The
          # separator after the colon must START WITH A LITERAL SPACE - a
          # tab-first separator makes the line an ordinary paragraph. Each
          # definition ends with its line.
          rule %r/#{bol}(#{MARGIN})(\[\^)([^\]\n]+)(\]:)( )/ do
            groups Text, Punctuation, Name::Label, Punctuation, Text
            open_block(:defline, :defline, host: :footnote)
          end
          rule %r/#{bol}(#{MARGIN})(\*\[)([^\]\n]+)(\]:)( )/ do
            groups Text, Punctuation, Name::Entity, Punctuation, Text
            open_block :defline
          end
          rule %r/#{bol}(#{MARGIN})(\[)([^\]\n]+)(\]:)( )/ do
            groups Text, Punctuation, Name::Label, Punctuation, Text
            open_block :linkdest
          end

          # A definition-list term (`::`) and its definition (`:`). A term
          # may wrap onto lazy lines, and a definition's text is an item's.
          rule %r/#{bol}(#{MARGIN})(::)( +)(?=[ \t]*[^ \t\n])/ do
            groups Text, Punctuation, Text
            remember_host(:term)
            open_block :dlterm, :heading
          end
          rule %r/#{bol}#{root_margin}(:)( +[ \t]*)(\+)()$#{PLUS_NEXT}/ do
            if definition_term_before?
              groups Text, Punctuation, Text, Operator, Text
            else
              groups Text, Punctuation, Text, Text, Text
            end
            open_block :listitem, :quoteline
          end
          rule %r/#{bol}(#{MARGIN})(:)(?= +[ \t]*[^ \t\n])/ do
            groups Text, Punctuation
            open_block :listitem, :quoteline
          end

          # A blockquote marker must be followed by a space or end the line;
          # `>foo` and `>> x` are paragraphs, and `> > x` nests. What follows
          # a marker may open a block of its own, so the openers are tried
          # again there.
          rule %r/#{bol}(#{MARGIN})(>)(?= |$)/ do |m|
            groups Text, Punctuation
            record_quote_depth(quote_depth_on_line + 1)
            remember_host(:quote)
            rooted = state?(:quotestart) ? m[1] == ' ' : m[1].empty?
            if rooted
              state?(:quotestart) ? goto(:quotestart) : push(:quotestart)
            else
              state?(:quotestart) ? goto(:quoteline) : push(:quoteline)
            end
          end

          # A task can attach its first block on the marker line.
          rule %r/#{bol}#{root_margin}([-*](?:#{ATTRS})?)( +[ \t]*)(\[[^\]\n]\])( +[ \t]*)(\+)()$#{PLUS_NEXT}/ do
            groups Text, Punctuation, Text, Name::Constant, Text, Operator, Text
            open_block :listitem, :quoteline
          end

          rule %r/#{bol}#{root_margin}(#{OPENER_RUN})(\+)()$#{PLUS_NEXT}/ do |m|
            token Text, m[1]
            scanner = StringScanner.new(m[2])
            until scanner.eos?
              if (marker = scanner.scan(/(?:#{ORDERED}|\.)(?:#{ATTRS})?/))
                token Num::Integer, marker
              elsif (marker = scanner.scan(/[-*](?:#{ATTRS})?|>/))
                token Punctuation, marker
              else
                token Text, scanner.getch
              end
            end
            depth = quote_depth_on_line
            token(state?(:quotestart) && !quote_level_follows?(depth) ? Text : Operator, m[3])
            token Text, m[4]
            m[2].rstrip.end_with?('>') ? open_block(:quoteline) : open_block(:listitem, :quoteline)
          end

          # Task items before plain bullets, so the state marker is its own
          # token. The state is any single character, not only a space or an
          # x: `[>]` is deferred and `[-]` is dropped. A `+` is not a bullet in
          # Carve; it continues a container.
          rule %r/#{bol}(#{MARGIN})((?:[-*]|#{ORDERED})(?:#{ATTRS})?)( +)(\[[^\]\n]\])(?= +[ \t]*[^ \t\n])/ do
            groups Text, Punctuation, Text, Name::Constant
            open_block :listitem, :quoteline
          end

          # Bullets. A run of markers on one line opens nested lists at once
          # (`- - A`), and attributes may be glued straight onto the marker.
          rule %r/#{bol}(#{MARGIN})((?:[-*] +)*[-*](?:#{ATTRS})?)(?= +[ \t]*[^ \t\n])/ do
            groups Text, Punctuation
            open_block :listitem, :quoteline
          end

          # Ordered markers: numeric, alphabetic, roman, and the bare `.` that
          # continues the enclosing sequence.
          rule %r/#{bol}(#{MARGIN})(#{ORDERED}(?:#{ATTRS})?)(?= +[ \t]*[^ \t\n])/ do
            groups Text, Num::Integer
            open_block :listitem, :quoteline
          end
          rule %r/#{bol}(#{MARGIN})(\.(?:#{ATTRS})?)(?= +[ \t]*[^ \t\n])/ do
            groups Text, Num::Integer
            open_block :listitem, :quoteline
          end

          # Tables. The header marker, the alignment run and the separator row
          # are their own tokens; cell content is lexed inline. A row needs its
          # closing pipe.
          rule %r/#{bol}(#{MARGIN})(\|=[<>^v~]*)#{ROW_END}/ do
            groups Text, Operator
            open_block :tablerow
          end
          rule %r/#{bol}(#{MARGIN})(\|)#{ROW_END}/ do
            groups Text, Punctuation
            open_block :tablerow
          end
        end
      end

      state(:blockopeners, &block_openers('^'))
      state(:quoteopeners, &block_openers(''))

      state :block do
        # Front matter, only at the very start of the document. \A is what
        # keeps a `---yaml` line mid-document from opening one.
        rule %r/\A(﻿?)(---)([a-zA-Z][\w-]*)?([ \t]*\n)(?=[\s\S]*?^---[ \t]*$)/ do
          groups Text, Punctuation, Keyword::Type, Text
          push :frontmatter
        end

        # A comment fence (%%% or longer) versus a one-line comment. The fence
        # has to be tried first: %%% also matches the one-line form. Only a
        # run of the SAME length closes it, so the width is closed over the
        # way #push_fence does it, and an opener with no such closer below it
        # is the one-line form. Text after either run is part of the comment.
        rule %r/^(#{MARGIN})(%%%+)([^\n]*)(\n)/ do |m|
          closer = %r/^([ \t]*)(%{#{m[2].length}})(?!%)([^\n]*)$/
          unless closer_below?(closer, m[2].length)
            # The tokens of the one-line rule below. Rouge 3 has no
            # fallthrough! to hand the line on to it.
            token Text, m[1]
            token Comment::Preproc, '%%'
            token Comment, m[2][2..] + m[3]
            token Text, m[4]
            next
          end

          groups Text, Comment::Preproc, Comment, Text
          push do
            rule closer do
              groups Text, Comment::Preproc, Comment
              pop!
            end
            rule %r/\n/, Comment
            rule %r/[^\n]+\n?/, Comment
          end
        end
        rule %r/^(#{MARGIN})(%%)([^\n]*)$/ do
          groups Text, Comment::Preproc, Comment
        end

        rule %r/^(\+)()$#{PLUS_NEXT}/ do |m|
          if continuation_host_before?
            groups Operator, Text
          else
            token Text, m[0]
            push :paragraph
          end
        end

        mixin :blockopeners

        # A standalone attribute block, which may span lines.
        rule %r/^(#{MARGIN})(#{ATTRS_LINE})/ do
          groups Text, Name::Attribute
        end

        # Any other line with content starts a paragraph.
        rule %r/^(?=#{MARGIN}\S)/ do
          @lone_image = !@current_stream.check(IMAGE_LINE).nil?
          @indented = @current_stream.check(/[ \t]/) ? true : false
          push :paragraph
        end

        mixin :inline
      end

      # A paragraph, and the start of each line after its first: a line that
      # opens a block interrupting it ends it, anything else continues it, so
      # a list marker or a caption under prose is prose.
      state :paragraph do
        rule(/\n/) { token Text; goto :paraline }
        mixin :inlinecontent
        rule PLAIN, Text
        rule %r/./, Text
      end

      state :paraline do
        rule(%r/^(?=[ \t]*(?:\n|\z))/) { pop! }
        rule(%r/^(?=\+$#{PLUS_NEXT})/) do
          continuation_host_before? ? pop! : continue_paragraph(:paragraph)
        end
        rule(%r/^(?=#{MARGIN}(?:#{INTERRUPT}))/) { pop! }
        rule(%r/^(?=#{MARGIN}(`{3,}|~{3,}))/) { |m| fence_closed_below?(m[1]) ? pop! : continue_paragraph(:paragraph) }
        rule(%r/^(?=#{MARGIN}\^[ \t])/) { @lone_image ? pop! : continue_paragraph(:paragraph) }
        # An indented paragraph sits in a container, so a list marker below it
        # opens a sublist or the next item rather than continuing it.
        rule(%r/^(?=#{MARGIN}#{LIST_MARKER})/) { @indented ? pop! : continue_paragraph(:paragraph) }
        rule(//) { continue_paragraph(:paragraph) }
      end

      # The text of a list item, a definition or a definition term. The line
      # after it may also start the next item or definition.
      { listitem: Text, dlterm: Generic::Heading }.each do |name, tok|
        line = :"#{name}line"
        state name do
          rule(/\n/) { token Text; goto line }
          mixin :inlinecontent
          rule PLAIN, tok
          rule(/./) { token plain_token }
        end

        state line do
          rule(%r/^(?=[ \t]*(?:\n|\z))/) { pop! }
          if name == :listitem
            rule %r/^(\+)()$#{PLUS_NEXT}/ do
              groups Operator, Text
              goto name
            end
          end
          rule(%r/^(?=#{MARGIN}(?:#{INTERRUPT}|#{LIST_MARKER}|:[ \t]))/) { pop! }
          rule(%r/^(?=#{MARGIN}(`{3,}|~{3,}))/) { |m| fence_closed_below?(m[1]) ? pop! : goto(name) }
          rule(//) { goto name }
        end
      end

      # Right after a blockquote marker: a block opener, or quoted text.
      state :quotestart do
        mixin :quoteopeners
        rule(//) { goto :quoteline }
      end

      state :frontmatter do
        rule %r/^(---)([ \t]*)$/ do
          groups Punctuation, Text
          pop!
        end
        rule %r/\n/, Comment::Special
        rule %r/[^\n]+\n?/, Comment::Special
      end

      state :defline do
        rule %r/$/, Text, :pop!
        mixin :inlinecontent
        rule PLAIN, Text
        rule %r/[^\n]/, Text
      end

      state :heading do
        rule %r/$/, Text, :pop!
        mixin :lineverbatim
        mixin :inlinecontent
        rule PLAIN, Generic::Heading
        rule %r/[^\n]/, Generic::Heading
      end

      state :quoteline do
        rule %r/$/, Text, :pop!
        mixin :lineverbatim
        mixin :inlinecontent
        rule PLAIN, Generic::Emph
        rule %r/[^\n]/, Generic::Emph
      end

      state :caption do
        rule %r/$/, Text, :pop!
        mixin :lineverbatim
        mixin :inlinecontent
        rule PLAIN, Generic::Subheading
        rule %r/[^\n]/, Generic::Subheading
      end

      state :tablerow do
        rule %r/$/, Text, :pop!
        # A header cell marker, optionally carrying an alignment run. The pipe
        # is part of it, so `|=` reads as one construct.
        rule %r/\|=[<>^v~]*/, Operator
        # A separator row cell, in the native and the GFM spelling.
        rule %r/(?<=\|)[ \t]*:?-{2,}:?[ \t]*(?=\|)/, Punctuation
        rule %r/(?<=\|)[ \t]*[<>^v~]{1,2}[ \t]*(?=\|)/, Operator
        rule %r/\|/, Punctuation
        mixin :inlinecontent
        rule PLAIN_NO_PIPE, Text
        rule %r/[^\n|]/, Text
      end

      state :linkdest do
        rule %r/$/, Text, :pop!
        rule %r/<[^>\n]*>/, Name::Tag
        rule %r/"[^"\n]*"/, Str::Double
        rule %r/[^\s\n]+/, Name::Tag
        # Any Unicode whitespace, not only space and tab: a destination can be
        # preceded by U+202F and friends, and a class of two characters leaves
        # the state with nothing to match.
        rule %r/[^\S\n]+/, Text
      end

      # ------------------------------------------------------------------
      # Inline level
      # ------------------------------------------------------------------
      state :inline do
        mixin :inlinecontent
        rule %r/\n/, Text
        rule %r/./, Text
      end

      state :lineverbatim do
        rule %r/(!)(`+)(?!`)((?:(?!(?<!`)\2(?!`))[^\n])*)((?<!`)\2(?!`)|$)/ do
          groups Operator, Punctuation, Literal, Punctuation
        end
        rule %r/(\$\$?)(`+)(?!`)((?:(?!(?<!`)\2(?!`))[^\n])*)((?<!`)\2(?!`)|$)/ do
          groups Operator, Punctuation, Str::Other, Punctuation
        end
        rule %r/(`+)(?!`)((?:(?!(?<!`)\1(?!`))[^\n])*)((?<!`)\1(?!`)|$)/ do
          groups Punctuation, Str::Backtick, Punctuation
        end
      end

      state :inlinecontent do
        # An escape wins over every delimiter that follows it. A backslash at
        # END OF LINE escapes nothing - it is a hard break, and needs its own
        # rule because the general form requires a following character.
        rule %r/\\(?=\n|$)/, Str::Escape
        rule %r/\\[!-\/:-@\[-`{-~]/, Str::Escape

        # A trailing comment runs to end of line from anywhere on it.
        rule %r/(%%)([^\n]*)$/ do
          groups Comment::Preproc, Comment
        end

        # Verbatim families first: nothing inside them is markup. The literal
        # form is a `!` PREFIX on a code span, not a trailing attribute, and it
        # has to be tried before plain inline code or the `!` would be read as
        # text and the span as ordinary code.
        rule %r/(!)(`+)([^\n]*?)(\2)/ do
          groups Operator, Punctuation, Literal, Punctuation
        end
        rule %r/(\$\$)(`+)([^\n]*?)(\2)/ do
          groups Operator, Punctuation, Str::Other, Punctuation
        end
        rule %r/(\$)(`+)([^\n]*?)(\2)/ do
          groups Operator, Punctuation, Str::Other, Punctuation
        end
        rule %r/(`+)([^\n]*?)(\1)/ do
          groups Punctuation, Str::Backtick, Punctuation
        end

        # The reserved include directive `{{ path #section @key:value }}`
        # (PART 9 section 19, grammar.ebnf `include_directive`). The core
        # leaves it literal; a processor expands it only when a host supplies a
        # resolver.
        #
        # One directive rule, because its own selector is spelled with constructs this
        # lexer already knows: `#section` is the tag rule below and an option
        # slot is the mention rule, so without this `#intro` came out coloured
        # as a hashtag inside a path. After the verbatim family, so a directive
        # in a code span stays literal; before every other brace rule, none of
        # which can spell `{{`.
        # An unterminated `{{` never opens the state and stays the ordinary
        # text the processor treats it as.
        rule %r/(\{\{)([ \t]+)((?:"(?:\\.|[^"\\])*"|[^#@}\s"][^#@}\s]*))/ do |m|
          if closer_ahead?(:include, /[ \t]\}\}/)
            groups Punctuation, Text, Name::Namespace
            push :includeparts
          else
            token plain_token, m[0]
          end
        end

        # The braced families. Each opener consumes only its `{` here, so an
        # unclosed one leaves the character after it to the rules below, and
        # its closer must be on the line - looked up in a per-line cache, so
        # a run of unclosed openers stays linear.
        #
        # CriticMarkup substitution and forced strike share `{~`; the first of
        # `~>` and `~}` decides which one it is.
        rule %r/\{(?=~(?!~\}))/ do
          next token(plain_token) unless closer_ahead?(:tilde, /~\}/)

          enter_braced(:tildebrace)
        end

        # A CriticMarkup comment. Without its closer, `{#id}` is an attribute
        # block.
        # The scanner's match is read before #check replaces it.
        rule %r/\{(?=\#)/ do |m|
          brace = m[0]
          if closer_ahead?(:criticcomment, /\#\}/, @current_stream.charpos + 1)
            enter_braced(:criticcomment)
          elsif (tail = @current_stream.check(ATTRS_TAIL))
            token Name::Attribute, brace
            consume_as(Name::Attribute, tail)
          else
            token plain_token, brace
          end
        end

        # The FORCED emphasis family and the other braced inlines. Braces make
        # a delimiter apply where the bare form would not - `my{_path_}name`
        # is underline inside a word - so the content is emphasis and the
        # braces are its delimiters, not an attribute block. Sup and sub are
        # braced-only in Carve: a bare `^x^` or `,x,` is literal text.
        BRACED.each do |char, (_, name)|
          delimiter = Regexp.escape(char)
          rule %r/\{(?=#{delimiter}(?!#{delimiter}\}))/ do
            if closer_ahead?(name, /#{delimiter}\}/, @current_stream.charpos + 2)
              enter_braced(name)
            else
              token plain_token
            end
          end
        end
        rule %r/\{(?=>>)/ do
          if closer_ahead?(:criticnote, /<<\}/, @current_stream.charpos + 3)
            enter_braced(:criticnote, 2)
          else
            token plain_token
          end
        end
        rule %r/\{(?=%)/ do
          if closer_ahead?(:bracedcomment, /%\}/, @current_stream.charpos + 1)
            token Comment::Preproc
            push :bracedcomment
            push :preprocchar
          else
            token plain_token
          end
        end

        # An inline footnote carries content; a reference carries a label.
        # Both bracketed bodies need a closing `]` before the paragraph ends;
        # an opener without one is text, as it is in the engine.
        rule %r/\^\[/ do
          if (scope = bracket_ahead?)
            token Punctuation
            push :"inlinefootnote_#{scope}"
          else
            token plain_token
          end
        end
        rule %r/(\[\^)([^\[\]\n]+)(\])/ do
          groups Punctuation, Name::Label, Punctuation
        end

        # A citation before a link: both open with `[`, and `[@key]` or
        # `[+@key]` would otherwise be read as a link label.
        rule %r/(\[)(\+?@[^\[\]\n]+)(\])/ do
          groups Punctuation, Name::Variable, Punctuation
        end

        # Image, then link, then a bare span. All three share the `[...]` shape
        # and differ only in the prefix and what follows.
        rule %r/(!#{LABEL})(\()([^)\n]*)(\))/ do
          groups Str::Other, Punctuation, Name::Tag, Punctuation
        end
        rule %r/(!#{LABEL})(#{LABEL})/ do
          groups Str::Other, Name::Label
        end
        rule %r/(#{LABEL})(\()([^)\n]*)(\))/ do
          groups Name::Entity, Punctuation, Name::Tag, Punctuation
        end
        rule %r/(#{LABEL})(#{LABEL})/ do
          groups Name::Entity, Name::Label
        end
        rule %r/#{LABEL}(?=#{ATTRS})/, Name::Entity

        # A cross-reference to a heading id.
        rule %r/(<\/)(\#[\w-]+)(>)/ do
          groups Punctuation, Name::Namespace, Punctuation
        end
        # An autolink.
        rule %r/(<)([a-zA-Z][\w+.-]*:[^>\s]+|[^>\s@]+@[^>\s]+)(>)/ do
          groups Punctuation, Name::Tag, Punctuation
        end

        # The `:name[...]` extension form.
        rule %r/(:)([a-zA-Z][\w-]*)(\[)/ do
          if (scope = bracket_ahead?)
            groups Punctuation, Name::Function, Punctuation
            push :"rolebody_#{scope}"
          else
            token plain_token
          end
        end

        # A code callout marker, and a symbol shortcode - whose name may start
        # with a sign, as in `:+1:`.
        rule %r/<\d+>/, Name::Constant
        rule %r/(?<![\w:]):[\w+-]+:(?![\w:])/, Name::Constant

        # An attribute block attached to the construct before it.
        rule ATTRS, Name::Attribute

        # Bare emphasis delimiters, Carve's / * _ ~ = set. Whether one opens is
        # decided in #open_bare, from the characters on both sides and from
        # whether a closer follows on the line; what it encloses is lexed as
        # inline content. `==>` is left whole for the typographic rule.
        rule %r/[*\/_~]|=(?!=>)/ do |m|
          open_bare(m[0])
        end

        # A mention and a tag, each one token: the sigil is part of the name
        # rather than punctuation beside it.
        rule %r/(?<![\w\/])@[\w][\w.-]*/, Name::Variable::Magic
        rule %r/(?<![\w&])\#[\w][\w-]*/, Name::Variable::Instance

        # Typographic runs, longest first: an arrow is not an en dash plus a
        # stray angle bracket, and `---` is not `--` plus `-`.
        rule %r/<-->|<==>|<=>|-->|<--|==>|<==|->|<-/, Operator
        rule %r/(?<!-)---(?!-)|(?<!-)--(?!-)/, Punctuation
        rule %r/\.\.\./, Punctuation
      end

      # The tail of an include directive: its selector, option slots, and
      # anything else written there. Scoped BY PART - the opener rule is what
      # keeps the tag and mention rules out, so painting one token buys nothing,
      # and a reader wants the path to look like a path.
      #
      # A part that is neither a section nor an option stays plain text rather
      # than being refused, matching the processor, which leaves a malformed
      # directive alone. A newline pops: the directive requires its closer on
      # the same line, so anything else is not one.
      state :includeparts do
        rule %r/[ \t]+/, Text
        rule %r/\}\}/, Punctuation, :pop!
        rule %r/#[A-Za-z0-9_][\w-]*/, Name::Label
        rule %r/(@[A-Za-z_][\w-]*)(:)([^\s}]+)/ do
          groups Name::Attribute, Punctuation, Literal
        end
        rule %r/[^\s}]+/, Text
        rule %r/\}/, Text
        rule %r/\n/, Text, :pop!
      end

      # The body of a bare emphasis run. A same-kind delimiter that cannot
      # close is content (`*a *b* c*` closes at `b*`), and the run ends with
      # its line in case a construct inside took the closer the opener saw.
      #
      # NO LOOKBEHIND IN A RULE. Rouge before 5 scans without a fixed anchor,
      # so a lookbehind cannot see what precedes the scan position; the
      # character before a closer is read in #close_bare instead.
      BARE.each do |char, (name, _, _, _)|
        state name do
          rule(%r/#{Regexp.escape(char)}(?![\p{L}\p{N}])/) { close_bare(/\s/) }
          rule(/$/) { pop! }
          rule(/#{Regexp.escape(char)}/) { token plain_token }
          mixin :inlinecontent
          rule(PLAIN) { token plain_token }
          rule(/./) { token plain_token }
        end
      end

      # Bold italic in one delimiter pair, in both nesting orders. Its own
      # delimiters inside it are content unless they close it.
      # A comment inside it ends at its closer.
      {
        bolditalic: ['\*\/', /\s/, '(?<=\S)\*\/'],
        italicbold: ['\/\*(?!\w)', /[\s*]/, '(?<![\s*])\/\*(?!\w)']
      }.each do |name, (closer, refused_before, closer_in_line)|
        state name do
          rule(/#{closer}/) { close_bare(refused_before) }
          rule(/$/) { pop! }
          rule %r/(%%)((?:(?!#{closer_in_line})[^\n])*)/ do
            groups Comment::Preproc, Comment
          end
          rule(%r/[*\/]/) { token plain_token }
          mixin :inlinecontent
          rule(PLAIN) { token plain_token }
          rule(/./) { token plain_token }
        end
      end

      # The rest of an opener whose `{` was already emitted.
      state :punctchar do
        rule(/[^\n]/) { token Punctuation; pop! }
      end
      state :preprocchar do
        rule(/[^\n]/) { token Comment::Preproc; pop! }
      end

      # Braced bodies, flat up to their closer.
      BRACED.each do |char, (tok, name)|
        closer = /#{Regexp.escape(char)}\}/
        state name do
          rule closer, Punctuation, :pop!
          rule(/$/) { pop! }
          rule %r/(?:(?!#{closer})[^\n])+/, tok
        end
      end

      state :tildebrace do
        rule %r/~>/, Operator, :tildenew
        rule %r/~\}/, Punctuation, :pop!
        rule(/$/) { pop! }
        rule %r/(?:(?!~[>}])[^\n])+/, Generic::Deleted
      end

      # The new side of a substitution. Its closer ends the whole construct.
      state :tildenew do
        rule(/~\}/) { token Punctuation; pop!(2) }
        rule(/$/) { pop!(2) }
        rule %r/(?:(?!~\})[^\n])+/, Generic::Inserted
      end

      state :criticcomment do
        rule %r/\#\}/, Punctuation, :pop!
        rule(/$/) { pop! }
        rule %r/(?:(?!\#\})[^\n])+/, Comment
      end

      state :criticnote do
        rule %r/<<\}/, Punctuation, :pop!
        rule(/$/) { pop! }
        rule %r/(?:(?!<<\})[^\n])+/, Comment
      end

      state :bracedcomment do
        rule %r/%\}/, Comment::Preproc, :pop!
        rule(/$/) { pop! }
        rule %r/(?:(?!%\})[^\n])+/, Comment
      end

      # Both bodies end at their bracket, or where their block ends when a
      # construct inside consumed the bracket the opener saw. The newline is
      # left to the block, which decides what the next line opens.
      { inlinefootnote: Generic::Emph, rolebody: Name::Function }.each do |body, tok|
        BODY_ENDS.each do |scope, ends|
          state :"#{body}_#{scope}" do
            rule %r/\]/, Punctuation, :pop!
            rule(%r/(?=#{ends.source}|\n?\z)/) { pop! }
            # The newline is handed back so the block reads the fence line.
            rule(FENCE_NEXT) do |m|
              if fence_closed_below?(m[1])
                m.pos -= 1
                pop!
              else
                token Text
              end
            end
            mixin :inlinecontent
            rule PLAIN_NO_BRACKET, tok
            rule %r/[^\]\n]/, tok
            rule %r/\n/, Text
          end
        end
      end

      # The lexer states cannot carry the open containers' marker columns, so
      # the `+` scope is settled afterwards from a document-level pass: a `+`
      # it names is the continuation operator, every other `+` the states
      # gave Operator is text.
      def stream_tokens(str, &block)
        markers = CarveContinuation.markers(str).to_h { |offset| [offset, true] }
        candidates = CarveContinuation.candidates(str).to_h { |offset| [offset, true] }
        pos = 0
        super(str) do |tok, val|
          if val.include?('+') && candidates.any?
            retag_plus(tok, val, pos, markers, candidates, &block)
          else
            yield tok, val
          end
          pos += val.length
        end
      end

      private

      def retag_plus(tok, val, pos, markers, candidates)
        run = +''
        val.each_char.with_index do |ch, i|
          scope = if ch != '+' || !candidates[pos + i] then tok
                  elsif markers[pos + i] then Operator
                  elsif tok == Operator then Text
                  else tok
                  end
          if scope != tok
            yield tok, run unless run.empty?
            run = +''
            yield scope, ch
          else
            run << ch
          end
        end
        yield tok, run unless run.empty?
      end

      # The token a state gives a character that opens nothing.
      PLAIN_TOKENS = {
        heading: Generic::Heading, quoteline: Generic::Emph,
        caption: Generic::Subheading, dlterm: Generic::Heading, bolditalic: Generic::Strong,
        italicbold: Generic::Strong
      }.merge(BARE.values.to_h { |name, tok, _, _| [name, tok] })
        .merge(BODY_ENDS.keys.flat_map do |scope|
          [[:"inlinefootnote_#{scope}", Generic::Emph], [:"rolebody_#{scope}", Name::Function]]
        end.to_h).freeze

      # Italic or underline inside strong, or the reverse, reads as strong,
      # the token the combined delimiters have always had.
      def plain_token
        name = state.name
        if %i[emph underline].include?(name) && in_state?(:strong)
          Generic::Strong
        else
          PLAIN_TOKENS.fetch(name, Text)
        end
      end

      # Decide whether the bare delimiter +char+, just consumed, opens a run.
      # It opens when the characters around it allow it and a closer follows
      # on its line; otherwise it is plain text. `/*` and `*/` open bold
      # italic first, with the engine's guards for each order.
      def open_bare(char)
        text = @current_stream.string
        pos = @current_stream.charpos
        before = pos > 1 ? text[pos - 2] : nil
        before = nil if before == "\n"
        after = text[pos]
        name, _, refused_before, refused_after = BARE[char]

        limit = enclosing_closer(pos)

        if char == '/' && after == '*' && text[pos + 1].to_s.match?(/\S/) &&
           closer_ahead?(:bolditalic, COMBINED_CLOSERS[:bolditalic], pos + 2, masked: :combined, before: limit)
          token Punctuation
          push :bolditalic
          return push(:punctchar)
        end

        if char == '*' && after == '/' && !before.to_s.match?(/[\w*\/]/) &&
           text[pos + 1].to_s.match?(/\S/) && !(text[pos + 1] == '*' && text[pos + 2].to_s.match?(/[\s*]/)) &&
           closer_ahead?(:italicbold, COMBINED_CLOSERS[:italicbold], pos + 2, masked: :combined, before: limit)
          token Punctuation
          push :italicbold
          return push(:punctchar)
        end

        if after && !after.match?(refused_after) && !(before && before.match?(refused_before)) &&
           closer_ahead?(name, BARE_CLOSERS[name], pos, masked: :bare, before: limit)
          token Punctuation
          return push(name)
        end

        token plain_token
      end

      BARE_CLOSERS = BARE.to_h do |char, (name, _, _, _)|
        [name, %r/(?<=\S)#{Regexp.escape(char)}(?![\p{L}\p{N}])/]
      end.freeze
      COMBINED_CLOSERS = {
        bolditalic: %r/(?<=\S)\*\//, italicbold: %r/(?<![\s*])\/\*(?!\w)/
      }.freeze

      # Where the run the scanner is in closes, if it is in one: a run opened
      # inside it must close first, so `*a /b* c/` is strong `a /b`.
      def enclosing_closer(pos)
        name = state.name
        if BARE_CLOSERS.key?(name)
          closer_at(name, BARE_CLOSERS[name], pos, masked: :bare)
        elsif COMBINED_CLOSERS.key?(name)
          closer_at(name, COMBINED_CLOSERS[name], pos, masked: :combined)
        end
      end

      # A closer candidate inside a bare run, just consumed: it closes unless
      # the character before it is one +refused_before+ matches.
      def close_bare(refused_before)
        text = @current_stream.string
        at = @current_stream.charpos - @current_stream[0].length
        if at.positive? && !text[at - 1].match?(refused_before)
          token Punctuation
          pop!
        else
          token plain_token
        end
      end

      # Emit the `{` of a braced opener and enter +name+, whose remaining
      # opener characters come next.
      def enter_braced(name, rest = 1)
        token Punctuation
        push name
        rest.times { push :punctchar }
      end

      # Emit the next +text+ of the input as one +tok+ token.
      def consume_as(tok, text)
        literal = Regexp.new(Regexp.escape(text))
        push do
          rule(literal) { token tok; pop! }
        end
      end

      # Whether +pattern+ matches on the current line at or after +from+.
      # The matches of one line are found once per pattern and reused, which
      # keeps a line full of unclosed openers linear instead of quadratic.
      # A masked line hides what a bare closer cannot reach into: escapes,
      # code spans, braced inlines, link destinations and autolinks. A bare
      # run's line also ends at a trailing comment, which takes its closer.
      def closer_ahead?(key, pattern, from = @current_stream.charpos, masked: nil, before: nil)
        at = closer_at(key, pattern, from, masked: masked)
        !at.nil? && (before.nil? || at < before)
      end

      # The position of the first match of +pattern+ on the current line at or
      # after +from+, or nil.
      def closer_at(key, pattern, from = @current_stream.charpos, masked: nil)
        stream = @current_stream
        unless @closers_for.equal?(stream)
          @closers_for = stream
          @closers = {}
        end
        pos = stream.charpos
        entry = @closers[key]
        unless entry && pos >= entry[0] && pos <= entry[1]
          text = stream.string
          first = pos.zero? ? 0 : (text.rindex("\n", pos - 1) || -1) + 1
          last = text.index("\n", pos) || text.length
          line = text[first...last]
          line = mask_opaque(line) if masked
          line = line[0...line.index('%%')] if masked == :bare && line.include?('%%')
          hits = []
          line.scan(pattern) { hits << first + Regexp.last_match.begin(0) }
          entry = @closers[key] = [first, last, hits]
        end
        entry[2].bsearch { |at| at >= from }
      end

      OPAQUE = /\\.|(?<!`)(`+)(?!`).*?(?<!`)\1(?!`)|\]\([^)\n]*\)|<[^<>\s]+>/.freeze

      def mask_opaque(line)
        line = line.gsub(OPAQUE) { |span| "\u0001" * span.length }
        # Braced inlines pair up in code: a regex scanning from every unclosed
        # `{*` to the end of the line is quadratic. Once a kind has no closer
        # left, no later opener of that kind can have one either.
        '*/_^,=+~#%-'.each_char do |kind|
          at = 0
          while (open = line.index("{#{kind}", at))
            close = line.index("#{kind}}", open + 3)
            break unless close

            line[open...close + 2] = "\u0001" * (close + 2 - open)
            at = close + 2
          end
        end
        line
      end

      # The scope of the block a bracketed body opens in, when a `]` outside
      # escapes and code spans follows before that block ends; nil otherwise.
      # The brackets of one block are found in one pass and reused, so a run
      # of unclosed openers does not rescan it once each.
      def bracket_ahead?
        stream = @current_stream
        pos = stream.charpos
        scope = body_scope
        @brackets = {} unless @brackets_for.equal?(stream)
        @brackets_for = stream
        entry = @brackets[scope]
        unless entry && pos < entry[0]
          text = stream.string
          last = body_end(text, pos, scope)
          hits = []
          text[pos...last].scan(BRACKET_SCAN) { hits << pos + $~.begin(0) if $~[0] == ']' }
          entry = @brackets[scope] = [last, hits]
        end
        entry[1].bsearch { |at| at >= pos } ? scope : nil
      end

      # Where a body opened at +pos+ must end: the first block end, or the
      # first closed fence, after it.
      def body_end(text, pos, scope)
        ends = BODY_ENDS[scope]
        last = text.index(ends, pos) || text.length
        return last if scope == :line

        at = pos
        while (fence = text.index(FENCE_NEXT, at)) && fence < last
          return fence if fence_closed_below?($~[1], fence + 1)

          at = fence + 1
        end
        last
      end

      BRACKET_SCAN = /\\.|(?<!`)(`+)(?!`).*?(?<!`)\1(?!`)|\]/.freeze

      # The scope of the nearest enclosing block state. An indented paragraph
      # sits in a container, so the next list marker ends it as it ends an item.
      def body_scope
        stack.reverse_each do |s|
          scope = BODY_SCOPE[s.name]
          next unless scope
          return :item if scope == :para && @indented

          return scope
        end
        :para
      end

      # Whether +closer+ matches a line below the current position. A miss
      # is remembered per +key+, because every later opener of the same kind
      # would miss too - without that, a run of unclosed openers rescans the
      # rest of the document once each.
      def closer_below?(closer, key, from = @current_stream.charpos)
        stream = @current_stream
        @closer_misses = {} unless @closer_misses_for.equal?(stream)
        @closer_misses_for = stream
        return false if @closer_misses[key]

        found = stream.string.index(closer, from)
        @closer_misses[key] = true unless found
        !found.nil?
      end

      # Enter the state of a block whose opener just matched, or none for an
      # opener that is a single token. After a blockquote marker the opener
      # replaces the quote's start state, and a single-token opener hands the
      # rest of the line to quoted text.
      def open_block(name = nil, quoted = name || :quoteline, host: nil)
        kind = host || (name == :listitem ? :list : name == :quoteline ? :quote : nil)
        remember_host(kind) if kind
        if state?(:quotestart)
          goto quoted
        elsif name
          push name
        end
      end

      def remember_host(kind)
        @host_stream = @current_stream
        @last_host_pos = @current_stream.pos
        @last_host_kind = kind
        if kind == :term
          @term_stream = @current_stream
          @term_pos = @last_host_pos
          @term_quote_depth = state?(:quotestart) ? quote_depth_on_line : 0
        elsif kind != :quote
          @term_pos = nil
        end
        @host_scan = StringScanner.new(@current_stream.string)
        @host_scan.pos = @last_host_pos
        @host_scan.scan(/[^\n]*\n/)
        @host_scan_valid = true
        @host_scan_fence = nil
        @host_scan_previous = nil
      end

      def quote_depth_on_line
        line_start = line_start_byte
        @quote_line_start == line_start ? @quote_depth_current : 0
      end

      def record_quote_depth(depth)
        @quote_line_start = line_start_byte
        @quote_depth_current = depth
      end

      def line_start_byte
        text = @current_stream.string
        pos = @current_stream.pos
        pos -= 1 while pos.positive? && text.getbyte(pos - 1) != 10
        pos
      end

      def next_line_after_current
        scan = StringScanner.new(@current_stream.string)
        scan.pos = @current_stream.pos
        return nil unless scan.scan(/[^\n]*\n/)

        scan.scan(/[^\n]*/)
      end

      def quote_level_follows?(depth)
        line = next_line_after_current
        return false unless line
        depth.times do
          return false unless line.start_with?('> ')

          line = line[2..]
        end
        !line.empty? && !line.match?(/\A[ \t]/)
      end

      def continuation_host_before?
        return false unless @host_stream.equal?(@current_stream) && @last_host_pos
        return false if @last_host_kind == :term
        return false if @last_host_kind == :quote && !quote_block_follows?

        return false unless @host_scan_valid

        limit = @current_stream.pos
        while (line = @host_scan.check(/[^\n]*\n/))
          break if @host_scan.pos + line.bytesize > limit

          @host_scan.scan(/[^\n]*\n/)
          line = line.chomp("\n")
          if @host_scan_fence
            fence = @host_scan_fence
            @host_scan_fence = nil if line.match?(/\A#{Regexp.escape(fence)}[#{Regexp.escape(fence[0])}]*[ \t]*\z/)
          elsif line.match?(/\A[ \t]*\z/)
            @host_scan_valid = false
          elsif (opening = line.match(/\A(`{3,}|~{3,})/))
            @host_scan_valid = false unless @host_scan_previous&.match?(/\A\+[ \t]*\z/)
            @host_scan_fence = opening[1]
          elsif line.match?(/\A(?:\#{1,6} +|::{1,}|\^ +|\||(?:[-*_][ \t]*){3,}|\[[^\]]+\]: )/)
            @host_scan_valid = false unless @host_scan_previous&.match?(/\A\+[ \t]*\z/)
          end
          @host_scan_previous = line
          return false unless @host_scan_valid
        end
        true
      end

      def definition_term_before?
        return false unless @term_stream.equal?(@current_stream) && @term_pos
        depth = state?(:quotestart) ? quote_depth_on_line : 0
        return false unless depth == @term_quote_depth

        between = @current_stream.string.byteslice(@term_pos...@current_stream.pos)
        lines = between.split("\n", -1)
        lines.shift
        lines.pop
        if depth.positive?
          prefix = '> ' * depth
          return false unless lines.all? { |line| line.empty? || line.start_with?(prefix) }

          lines.map! { |line| line.empty? ? line : line[prefix.length..] }
        end
        return false if lines.count { |line| line.match?(/\A[ \t]*\z/) } > 1

        lines.none? { |line| line.match?(/\A(?:\#{1,6} +|:{3,}|[-*] +|> |\|)/) }
      end

      def quote_block_follows?
        line = next_line_after_current
        return false unless line
        return false if line.empty? || line.match?(/\A[ \t]/)

        while line.start_with?('> ')
          line = line[2..]
          return false if line.empty? || line.match?(/\A[ \t]/)
        end
        line != '>'
      end

      def continue_paragraph(name)
        @lone_image = false
        goto name
      end

      # Whether a fence opened by +run+ on the current line is closed further
      # down. Only a closed fence interrupts a paragraph.
      def fence_closed_below?(run, line_start = @current_stream.charpos)
        text = @current_stream.string
        line_end = text.index("\n", line_start) || text.length
        closer = %r/^[ \t]*#{Regexp.escape(run[0])}{#{run.length},}[ \t]*$/
        closer_below?(closer, run, line_end)
      end

      # Lex the tail of a fence or container opener line without leaving the
      # current state: a quoted title, a bracketed label and an attribute
      # block, each as its own token.
      def lex_info_string(text)
        return if text.nil? || text.empty?

        scanner = StringScanner.new(text)
        until scanner.eos?
          if (m = scanner.scan(%r/"[^"\n]*"/))
            token Str::Double, m
          elsif (m = scanner.scan(%r/\[[^\]\n]*\]/))
            token Name::Label, m
          elsif (m = scanner.scan(ATTRS))
            token Name::Attribute, m
          else
            token Text, scanner.getch
          end
        end
      end

      # Enter a fenced block. The payload is opaque to Carve, so it either goes
      # to a lexer for the declared language or comes out as one string token.
      #
      # The closer must be AT LEAST as long as the opener. A Rouge state cannot
      # carry the opener's width across rules, so the width is closed over here
      # instead of approximated - `~~~~` does not close a ```` ``` ```` block,
      # and a three-backtick line inside a four-backtick fence stays content.
      def push_fence(opener, language)
        char = Regexp.escape(opener[0])
        width = opener.length
        closer = %r/^[ \t]*#{char}{#{width},}[ \t]*$/

        sublexer = fence_lexer(language)
        sublexer&.reset!

        return push_quoted_fence(char, width, sublexer) if state?(:quotestart)

        push do
          rule closer, Punctuation, :pop!
          if sublexer
            # The opener's own newline, which is not part of the payload and
            # sits mid-line where the line rule below cannot reach it.
            rule %r/\n/, Text
            # WHOLE LINES, never fragments. A delegated lexer carries state
            # across calls, so handing it a piece of a line at a time makes it
            # tokenize the pieces rather than the line.
            rule %r/^.*\n?/ do |m|
              delegate sublexer, m[0]
            end
          else
            # Carve's own callout marker, which only survives where no
            # embedded language owns the payload.
            rule %r/<\d+>/, Name::Constant
            rule %r/[^\n<]+|<|\n/, Str::Backtick
          end
        end
      end

      # A fence opened after a blockquote marker. Every payload line carries
      # the quote prefix at the opener's depth, which is markup rather than
      # payload; a line with fewer markers leaves that quote and so ends the
      # fence too, while a deeper marker is payload.
      def push_quoted_fence(char, width, sublexer)
        pop!
        text = @current_stream.string
        pos = @current_stream.charpos
        line = text[((text.rindex("\n", pos - 1) || -1) + 1)...pos]
        depth = line[/\A#{QUOTE_PREFIX}/].to_s.count('>')
        prefix = %r/(?:[ \t]*>(?=[ \t]|$)){#{depth}}[ \t]?/

        push do
          rule %r/^(#{prefix})([ \t]*#{char}{#{width},})([ \t]*)$/ do
            groups Punctuation, Punctuation, Text
            pop!
          end
          rule(%r/^(?!#{prefix})/) { pop! }
          rule %r/^#{prefix}/, Punctuation
          if sublexer
            rule %r/\n/, Text
            rule(%r/[^\n]+\n?/) { |m| delegate sublexer, m[0] }
          else
            rule %r/<\d+>/, Name::Constant
            rule %r/[^\n<]+|<|\n/, Str::Backtick
          end
        end
      end

      # A lexer for the fence's declared language, or nil when there is no
      # language, none is known, or the name is ambiguous. Guessing is
      # deliberately not attempted: a wrong guess colours a sample as the wrong
      # language, which reads worse than leaving it plain.
      def fence_lexer(language)
        return nil if language.nil? || language.empty?

        return CsvTable.new if language == 'csv'
        return TsvTable.new if language == 'tsv'

        Lexer.find_fancy(language)
      rescue StandardError
        nil
      end
    end
  end
end
