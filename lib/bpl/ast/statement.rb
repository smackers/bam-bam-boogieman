module Bpl
  module AST
    class Statement
      Return = Statement.new
      def Return.to_s; "return;" end
    end
    
    class AssertStatement < Statement
      attr_accessor :expression
      def initialize(e); @expression = e end
      def to_s; "assert #{@expression};" end
    end
    
    class AssumeStatement < Statement
      attr_accessor :expression
      def initialize(e); @expression = e end
      def to_s; "assume #{@expression};" end
    end
    
    class HavocStatement < Statement
      attr_accessor :identifiers
      def initialize(ids); @identifiers = ids end
      def to_s; "havoc #{@identifiers * ", "};" end
    end
    
    class AssignStatement < Statement
      attr_accessor :lhs, :rhs
      def initialize(l,r); @lhs = l; @rhs = r end
      def to_s; "#{@lhs * ", "} := #{@rhs * ", "};" end
    end
    
    class CallStatement < Statement
      attr_accessor :procedure, :arguments, :assignments
      def initialize(p,args,xs=[])
        @procedure = p
        @arguments = args
        @assignments = xs
      end
      def forall?; @assignments.nil? end
      def to_s
        if forall? then
          lhs = "forall "
        else
          lhs = @assignments.empty? ? "" : (@assignments * ", ") + " := "
        end
        "call #{lhs}#{@procedure}(#{@arguments * ", "});"
      end
    end
    
    class IfStatement < Statement
      attr_accessor :condition, :block, :else
      def initialize(cond,blk,els); @condition = cond; @block = blk; @else = els end
      def to_s
        "if (#{@condition}) #{@block}#{@else.nil? ? "" : " else #{@else}" }"
      end
    end
    
    class WhileStatement < Statement
      attr_accessor :condition, :invariants, :block
      def initialize(cond,invs,blk)
        @condition = cond
        @invariants = invs
        @block = blk
      end
      def to_s
        invs = @invariants.empty? ? " " : "\n" + @invariants * "\n" + "\n"
        "while (#{@condition})#{invs}#{@block}"
      end
    end
    
    class BreakStatement < Statement
      attr_accessor :identifiers
      def initialize(ids); @identifiers = ids end
      def to_s
        tgts = @identifiers.empty? ? "" : " " + @identifiers * ", "
        "break#{tgts};"
      end
    end
    
    class GotoStatement < Statement
      attr_accessor :identifiers
      def initialize(ids); @identifiers = ids end
      def to_s; "goto #{@identifiers * ", "};" end
    end
    
    class Block
      attr_accessor :declarations, :statements
      def initialize(decls,stmts)
        @declarations = decls
        @statements = stmts
      end
      def to_s
        str = ""
        unless @declarations.empty?
          str << "\n"
          @declarations.each do |d|
            str << "#{d}\n"
          end
        end
        unless @statements.empty?
          str << "\n"
          @statements.each do |ls|
            ls[:labels].each do |lab|
              str << "#{lab}:\n"
            end
            str << "#{ls[:stmt]}\n" if ls[:stmt]
          end
        end
        "{#{str.gsub(/^(.*[^:\n])$/,"#{"  "}\\1")}}"
      end
    end

  end
end