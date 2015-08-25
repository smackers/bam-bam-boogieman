module Bpl
  module Transformation
    class Shadowing < Bpl::Pass

      def self.description
        "Create a shadow program."
      end

      depends :resolution, :ct_annotation

      def shadow(x) "#{x}.shadow" end
      def shadow_eq(x) "#{x} == #{shadow(x)}" end
      def decl(v)
        v.class.new(names: v.names.map(&method(:shadow)), type: v.type)
      end

      def shadow_copy(node)
        copy = bpl(node.to_s)
        copy.each do |expr|
          next unless expr.is_a?(StorageIdentifier)
          next if expr.declaration &&
                  expr.declaration.is_a?(ConstantDeclaration)
          expr.replace_with(StorageIdentifier.new(name: shadow(expr)))
        end
        copy
      end

      EXEMPTION_LIST = [
        '\$alloc',
        '\$free',
        'boogie_si_',
        '__VERIFIER_'
      ]
      EXEMPTIONS = /#{EXEMPTION_LIST * "|"}/

      def exempt? decl
        EXEMPTIONS.match(decl) && true
      end

      def run! program

        # duplicate global variables
        program.global_variables.each {|v| v.insert_after(decl(v))}

        # duplicate parameters, returns, and local variables
        program.each_child do |decl|
          next unless decl.is_a?(ProcedureDeclaration) && !exempt?(decl.name)

          public_inputs = decl.parameters.select{|p| p.attributes[:public_in]}
          public_outputs = decl.parameters.select{|p| p.attributes[:public_out]}
          declassified_outputs = decl.parameters.select{|p| p.attributes[:declassified_out]}
          public_returns = decl.returns.select{|p| p.attributes[:public_return]}
          declassified_returns = decl.returns.select{|p| p.attributes[:declassified_return]}

          return_variables = decl.returns.map{|v| v.names}.flatten

          decl.parameters.each {|d| d.insert_after(decl(d))}
          decl.returns.each {|d| d.insert_after(decl(d))}

          next unless decl.body

          # TODO assume equality at entry points on public inputs
          # TODO assume equality at exit points on public outputs
          # TODO assume equality at exit points on declassified outputs

          public_inputs.each do |p|
            length = p.attributes[:public_in].first
            p.names.each do |x|
              decl.append_children(:specifications,
                if length then
                  # NOTE we must know how to access this memory too...
                  # $load(_, x + 0) == $load(_, x.shadow + 0)
                  # $load(_, x + 1) == $load(_, x.shadow + 1)
                  # etc.
                  bpl("requires true;")
                else
                  bpl("requires #{shadow_eq x};")
                end
              )
            end
          end

          next # TODO RESUME RESTORATION FROM HERE TODO

          unless public_outputs.empty?
            lhs = declassified_outputs.map(&method(:shadow_eq)) * " && "
            lhs = if declassified_outputs.empty? then "" else "#{lhs} ==>" end
            rhs = public_outputs.map(&method(:shadow_eq)) * " && "
            decl.specifications << bpl("ensures #{lhs} #{rhs};")
          end

          last_lhs = nil

          decl.body.locals.each {|d| d.insert_after(decl(d))}

          decl.body.each do |stmt|
            case stmt
            when AssumeStatement

              # TODO should we be shadowing assume statements?
              stmt.insert_after(shadow_copy(stmt))

            when AssignStatement

              fail "Unexpected assignment statement: #{stmt}" unless stmt.lhs.length == 1

              # ensure the indicies to loads and stores are equal
              stmt.select{|e| e.is_a?(MapSelect)}.each do |ms|
                ms.indexes.each do |idx|
                  stmt.insert_before(bpl("assert #{shadow_eq idx};"))
                end
              end

              # shadow the assignment
              stmt.insert_after(shadow_copy(stmt))

              last_lhs = stmt.lhs.first

            when CallStatement
              if exempt?(stmt.procedure.name)
                stmt.assignments.each do |x|
                  stmt.insert_after("#{x} := #{shadow(x)}")
                end
              else
                (stmt.arguments + stmt.assignments).each do |arg|
                  arg.insert_after(shadow_copy(arg))
                end
              end

            when GotoStatement
              next if stmt.identifiers.length < 2
              unless stmt.identifiers.length == 2
                fail "Unexpected goto statement: #{stmt}"
              end
              stmt.insert_before(bpl("assert #{shadow_eq last_lhs};"))

            when ReturnStatement
              return_variables.each do |v|
                stmt.insert_before(bpl("assert #{shadow_eq v};"))
              end

            end
          end
        end
      end
    end
  end
end
