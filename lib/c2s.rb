#!/usr/bin/env ruby

require 'set'
require 'optparse'
require_relative 'c2s/version'
require_relative 'c2s/prelude'
require_relative 'c2s/frontend'
require_relative 'bpl/parser.tab'
require_relative 'bpl/ast/scope'
require_relative 'bpl/ast/binding'
require_relative 'bpl/ast/trace'
require_relative 'bpl/pass'
require_relative 'z3/model'

# parse @c2s-options comments in the source file(s) for additional options
ARGV.select{|f| File.extname(f) == '.bpl' && File.exists?(f)}.map do |f|
  File.readlines(f).grep(/@c2s-options (.*)/) do |line|
    line.gsub(/.* @c2s-options (.*)/,'\1').split.reverse.each do |arg|
      ARGV.unshift arg
    end
  end
end.flatten

PASSES = [:analysis, :transformation]
@passes = {}
@stages = []
@output_file = nil

root = File.expand_path(File.dirname(__FILE__))
Dir.glob(File.join(root,'bpl',"{#{PASSES * ","}}",'*.rb')).each do |lib|
  require_relative lib
  name = File.basename(lib,'.rb')
  kind = File.basename File.dirname(lib)
  klass = "Bpl::#{kind.capitalize}::#{name.classify}"
  @passes[name.to_sym] = Object.const_get(klass)
end

unless $quiet
  info "c2s version #{C2S::VERSION}, copyright (c) 2014, Michael Emmi".bold
  info "parameters: #{ARGV * " "}"
end

OptionParser.new do |opts|

  opts.banner = "Usage: #{File.basename $0} [options] FILE(s)"

  opts.separator ""
  opts.separator "Basic options:"

  opts.on("-h", "--help [PASS]", "Show this message") do |v|
    if v.nil?
      puts opts
    elsif klass = @passes[v.unhyphenate.to_sym]
      puts klass.help
    else
      puts "Unknown pass: #{v}"
    end
    exit
  end

  opts.on("--version", "Show version") do
    puts "#{File.basename $0} version #{C2S::VERSION || "??"}"
    exit
  end

  opts.on("-v", "--[no-]verbose", "Run verbosely? (default #{$verbose})") do |v|
    $verbose = v
    $quiet = !v
  end

  opts.on("-q", "--[no-]quiet", "Run quietly? (default #{$quiet})") do |q|
    $quiet = q
    $verbose = !q
  end

  opts.on("-w", "--[no-]warnings", "Show warnings? (default #{$show_warnings})") do |w|
    $show_warnings = w
  end

  opts.on("-k", "--[no-]keep-files", "Keep intermediate files? (default #{$keep})") do |v|
    $keep = v
  end

  opts.on("-o", "--output-file FILENAME") do |f|
    @output_file = f
  end

  PASSES.each do |kind|
    opts.separator ""
    opts.separator "#{kind.to_s.capitalize} passes:"

    @passes.each do |name,klass|
      next unless klass.name.split("::")[0..-2].last.downcase.to_sym == kind
      opts.on("--#{name.to_s.hyphenate}#{" [OPTS]" unless klass.options.empty?}", klass.brief) do |args|
        @stages << klass.new(case args
          when String
            (args || "").split(",").map{|s| k,v = s.split(":"); [k.to_sym,v]}.to_h
          else {}
          end)
      end
    end
  end

  opts.separator ""
  opts.separator "See --help PASS for more information about each pass."
  opts.separator ""

end.parse!

begin
  abort "Must specify a single source file." unless ARGV.size == 1
  src = ARGV[0]
  abort "Source file '#{src}' does not exist." unless File.exists?(src)

  src = timed 'Front-end' do
    C2S::process_source_file(src)
  end

  program = timed 'Parsing' do
    BoogieLanguage.new.parse(File.read(src))
  end

  program.source_file = src

  @stages.each do |analysis|
    timed analysis.class.name.split('::').last do
      analysis.run! program
    end
  end

  if @output_file
    timed('Writing transformed program') do
      $temp.delete @output_file
      File.write(@output_file, program)
    end
  else
    puts program.hilite
  end

ensure
  $temp.each{|f| File.unlink(f) if File.exists?(f)} unless $keep
end
