# -*- coding: utf-8 -*- #
# frozen_string_literal: true

module Rouge
  module Lexers
    # Carve is a post-Markdown lightweight markup language. Its inline
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
      title 'Carve'
      desc 'Carve, a post-Markdown lightweight markup language'

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
      # span written inside.
      ATTRS = %r/
        \{(?=[.:}'"]|\#[\w-]+[\s}]|[A-Za-z][\w-]*(?:[=\s}]|$))(?:
          "(?:[^"\\\n]|\\.)*"
          |'(?:[^'\\\n]|\\.)*'
          |\{[^{}\n]*\}
          |[^{}\n]
        )*\}
      /x.freeze

      # The same block as a STANDALONE ATTRIBUTE LINE, which may span lines.
      # The inline form deliberately cannot, because an unclosed inline `{`
      # would otherwise swallow the rest of the document.
      ATTRS_LINE = %r/
        \{(?=[.:}'"]|\#[\w-]+[\s}]|[A-Za-z][\w-]*(?:[=\s}]|$))(?:
          "(?:[^"\\]|\\.)*"
          |'(?:[^'\\]|\\.)*'
          |\{[^{}]*\}
          |[^{}]
        )*\}
      /x.freeze

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
      state :block do
        # Front matter, only at the very start of the document. \A is what
        # keeps a `---yaml` line mid-document from opening one.
        rule %r/\A(﻿?)(---)([a-zA-Z][\w-]*)?([ \t]*\n)(?=[\s\S]*?^---[ \t]*$)/ do
          groups Text, Punctuation, Keyword::Type, Text
          push :frontmatter
        end

        # A comment fence (%%% or longer) versus a one-line comment. The fence
        # has to be tried first: %%% also matches the one-line form.
        rule %r/^(#{MARGIN})(%%%+)([^\n]*)(\n)/ do
          groups Text, Comment::Preproc, Comment, Text
          push :commentfence
        end
        rule %r/^(#{MARGIN})(%%)([^\n]*)$/ do
          groups Text, Comment::Preproc, Comment
        end

        # A raw block: the `=FORMAT` info string routes the payload to that
        # output format verbatim. Emitted as one token including the `=`,
        # because the format word without its sigil is not the construct. The
        # payload is never a language, so it is never delegated.
        rule %r/^(#{MARGIN})(`{3,}|~{3,})([ \t]*)(=[a-zA-Z][\w+.-]*)([^\n]*)/ do |m|
          groups Text, Punctuation, Text, Keyword::Type
          token Text, m[5]
          push_fence(m[2], nil)
        end

        # A code fence. The first word of the info string names a language, and
        # a lexer for it highlights the payload - the one place this lexer
        # looks past Carve, because a reader of a `.crv` file expects an
        # embedded PHP sample to look like PHP.
        rule %r/^(#{MARGIN})(`{3,}|~{3,})([ \t]*)([a-zA-Z][\w+#.-]*)?([^\n]*)/ do |m|
          groups Text, Punctuation, Text, Name::Builtin
          lex_info_string(m[5])
          push_fence(m[2], m[4])
        end

        # Container divs. A reserved kind word (note, tip, figure, ...) names a
        # known container; `:::` followed by `|` is the layout form.
        rule %r/^(#{MARGIN})(:{3,})([ \t]*)(\|)/ do
          groups Text, Punctuation, Text, Operator
        end
        rule %r/^(#{MARGIN})(:{3,})([ \t]*)([a-zA-Z][\w-]*)?([^\n]*)/ do |m|
          groups Text, Punctuation, Text, Keyword::Namespace
          lex_info_string(m[5])
        end

        # A caption line attaches to the block above or below it.
        rule %r/^(#{MARGIN})(\^)([ \t]+)/ do
          groups Text, Punctuation, Text
          push :caption
        end

        # Headings. Carve has no setext form, so a `#` run is the only spelling
        # and a trailing `{...}` is NOT an attribute block here.
        rule %r/^(#{MARGIN})(\#{1,6})([ \t]+)/ do
          groups Text, Punctuation, Text
          push :heading
        end

        # Thematic breaks, before the list rules so `---` is not a bullet.
        rule %r/^#{MARGIN}(?:\*[ \t]*){3,}$/, Punctuation
        rule %r/^#{MARGIN}(?:-[ \t]*){3,}$/, Punctuation
        rule %r/^#{MARGIN}(?:_[ \t]*){3,}$/, Punctuation

        # Definition markers: footnote, link reference, abbreviation. The
        # separator after the colon must START WITH A LITERAL SPACE - a
        # tab-first separator makes the line an ordinary paragraph.
        rule %r/^(#{MARGIN})(\[\^)([^\]\n]+)(\]:)( )/ do
          groups Text, Punctuation, Name::Label, Punctuation, Text
          push :inline
        end
        rule %r/^(#{MARGIN})(\*\[)([^\]\n]+)(\]:)( )/ do
          groups Text, Punctuation, Name::Entity, Punctuation, Text
          push :inline
        end
        rule %r/^(#{MARGIN})(\[)([^\]\n]+)(\]:)( )/ do
          groups Text, Punctuation, Name::Label, Punctuation, Text
          push :linkdest
        end

        # A definition-list term (`::`) and its definition (`:`).
        rule %r/^(#{MARGIN})(::)([ \t]+)/ do
          groups Text, Punctuation, Text
          push :heading
        end
        rule %r/^(#{MARGIN})(:)(?=[ \t])/ do
          groups Text, Punctuation
        end

        # A blockquote marker must be followed by a space or end the line;
        # `>foo` is a paragraph.
        rule %r/^(#{MARGIN})(>+)(?=[ \t]|$)/ do
          groups Text, Punctuation
          push :quoteline
        end

        # Task items before plain bullets, so the state marker is its own
        # token. The state is any single character, not only a space or an x:
        # `[>]` is deferred and `[-]` is dropped.
        rule %r/^(#{MARGIN})((?:[-*+]|\d+[.)]|[A-Za-z]+[.)])(?:#{ATTRS})?)([ \t]+)(\[[^\]\n]\])/ do
          groups Text, Punctuation, Text, Name::Constant
        end

        # Bullets. A run of markers on one line opens nested lists at once
        # (`- - A`), and attributes may be glued straight onto the marker.
        rule %r/^(#{MARGIN})((?:[-*+][ \t]+)*[-*+](?:#{ATTRS})?)(?=[ \t]|$)/ do
          groups Text, Punctuation
        end

        # Ordered markers: numeric, alphabetic, roman, and the bare `.` that
        # continues the enclosing sequence.
        rule %r/^(#{MARGIN})((?:\d+|[A-Za-z]+)[.)](?:#{ATTRS})?)(?=[ \t]|$)/ do
          groups Text, Num::Integer
        end
        rule %r/^(#{MARGIN})(\.(?:#{ATTRS})?)(?=[ \t]|$)/ do
          groups Text, Num::Integer
        end

        # Tables. The header marker, the alignment run and the separator row
        # are their own tokens; cell content is lexed inline.
        rule %r/^(#{MARGIN})(\|=[<>^v~]*)/ do
          groups Text, Operator
          push :tablerow
        end
        rule %r/^(#{MARGIN})(\|)/ do
          groups Text, Punctuation
          push :tablerow
        end

        # A standalone attribute block, which may span lines.
        rule %r/^(#{MARGIN})(#{ATTRS_LINE})/ do
          groups Text, Name::Attribute
        end

        mixin :inline
      end

      state :frontmatter do
        rule %r/^(---)([ \t]*)$/ do
          groups Punctuation, Text
          pop!
        end
        rule %r/\n/, Comment::Special
        rule %r/[^\n]+\n?/, Comment::Special
      end

      state :commentfence do
        rule %r/^([ \t]*)(%%%+)([ \t]*)$/ do
          groups Text, Comment::Preproc, Text
          pop!
        end
        rule %r/\n/, Comment
        rule %r/[^\n]+\n?/, Comment
      end

      state :heading do
        rule %r/$/, Text, :pop!
        mixin :inlinecontent
        rule PLAIN, Generic::Heading
        rule %r/[^\n]/, Generic::Heading
      end

      state :quoteline do
        rule %r/$/, Text, :pop!
        mixin :inlinecontent
        rule PLAIN, Generic::Emph
        rule %r/[^\n]/, Generic::Emph
      end

      state :caption do
        rule %r/$/, Text, :pop!
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

        # CriticMarkup substitution and comment, before the forced family:
        # `{~old~>new~}` also matches the forced-strike shape.
        rule %r/(\{~)([^\n]*?)(~>)([^\n]*?)(~\})/ do
          groups Punctuation, Generic::Deleted, Operator, Generic::Inserted, Punctuation
        end
        rule %r/(\{\#)([^\n]*?)(\#\})/ do
          groups Punctuation, Comment, Punctuation
        end

        # The braced FORCED emphasis family. Braces make a delimiter apply
        # where the bare form would not - `my{_path_}name` is underline inside
        # a word - so the content is emphasis and the braces are its
        # delimiters, not an attribute block.
        rule %r/(\{\*)([^\n]+?)(\*\})/ do
          groups Punctuation, Generic::Strong, Punctuation
        end
        rule %r/(\{\/)([^\n]+?)(\/\})/ do
          groups Punctuation, Generic::Emph, Punctuation
        end
        rule %r/(\{_)([^\n]+?)(_\})/ do
          groups Punctuation, Generic::Emph, Punctuation
        end
        rule %r/(\{~)([^\n]+?)(~\})/ do
          groups Punctuation, Generic::Deleted, Punctuation
        end

        # Braced inline families. Sup and sub are braced-only in Carve: a bare
        # `^x^` or `,x,` is literal text.
        rule %r/(\{\^)([^\n]+?)(\^\})/ do
          groups Punctuation, Generic::Emph, Punctuation
        end
        rule %r/(\{,)([^\n]+?)(,\})/ do
          groups Punctuation, Generic::Emph, Punctuation
        end
        rule %r/(\{=)([^\n]+?)(=\})/ do
          groups Punctuation, Generic::Inserted, Punctuation
        end
        rule %r/(\{\+)([^\n]+?)(\+\})/ do
          groups Punctuation, Generic::Inserted, Punctuation
        end
        rule %r/(\{-)([^\n]+?)(-\})/ do
          groups Punctuation, Generic::Deleted, Punctuation
        end
        rule %r/(\{>>)([^\n]+?)(<<\})/ do
          groups Punctuation, Comment, Punctuation
        end
        rule %r/(\{%)(.*?)(%\})/ do
          groups Comment::Preproc, Comment, Comment::Preproc
        end

        # An inline footnote carries content; a reference carries a label.
        rule %r/\^\[/, Punctuation, :inlinefootnote
        rule %r/(\[\^)([^\]\n]+)(\])/ do
          groups Punctuation, Name::Label, Punctuation
        end

        # A citation before a link: both open with `[`, and `[@key]` or
        # `[+@key]` would otherwise be read as a link label.
        rule %r/(\[)(\+?@[^\]\n]+)(\])/ do
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
          groups Punctuation, Name::Function, Punctuation
          push :rolebody
        end

        # A code callout marker, and a symbol shortcode - whose name may start
        # with a sign, as in `:+1:`.
        rule %r/<\d+>/, Name::Constant
        rule %r/(?<![\w:]):[\w+-]+:(?![\w:])/, Name::Constant

        # An attribute block attached to the construct before it.
        rule ATTRS, Name::Attribute

        # Bare emphasis delimiters. Carve's bare set is / * _ ~ = and each
        # needs a non-space inner boundary so `a / b` stays literal.
        rule %r/(\/\*)([^\n]+?)(\*\/)/ do
          groups Punctuation, Generic::Strong, Punctuation
        end
        rule %r/(\*\/)([^\n]+?)(\/\*)/ do
          groups Punctuation, Generic::Strong, Punctuation
        end
        rule %r/(\*)(\S(?:[^\n]*?\S)?)(\*)/ do
          groups Punctuation, Generic::Strong, Punctuation
        end
        rule %r/(\/)(\S(?:[^\n]*?\S)?)(\/)/ do
          groups Punctuation, Generic::Emph, Punctuation
        end
        rule %r/(_)(\S(?:[^\n]*?\S)?)(_)/ do
          groups Punctuation, Generic::Emph, Punctuation
        end
        rule %r/(~)(\S(?:[^\n]*?\S)?)(~)/ do
          groups Punctuation, Generic::Deleted, Punctuation
        end
        rule %r/(=)(\S(?:[^\n]*?\S)?)(=)/ do
          groups Punctuation, Generic::Inserted, Punctuation
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

      state :inlinefootnote do
        rule %r/\]/, Punctuation, :pop!
        mixin :inlinecontent
        rule PLAIN_NO_BRACKET, Generic::Emph
        rule %r/[^\]\n]/, Generic::Emph
        rule %r/\n/, Text
      end

      state :rolebody do
        rule %r/\]/, Punctuation, :pop!
        mixin :inlinecontent
        rule PLAIN_NO_BRACKET, Name::Function
        rule %r/[^\]\n]/, Name::Function
        rule %r/\n/, Text
      end

      private

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

      # A lexer for the fence's declared language, or nil when there is no
      # language, none is known, or the name is ambiguous. Guessing is
      # deliberately not attempted: a wrong guess colours a sample as the wrong
      # language, which reads worse than leaving it plain.
      def fence_lexer(language)
        return nil if language.nil? || language.empty?

        Lexer.find_fancy(language)
      rescue StandardError
        nil
      end
    end
  end
end
