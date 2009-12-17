#!/usr/bin/env jruby
require 'rexml/document'
require 'rexml/xpath'
require 'net/http'
require 'rubygems'
require 'yaml'
require 'fileutils'
require 'ostruct'

module MavenGem
  module PomSpec
    def self.from_file(filename, options = {})
      puts "Reading POM from #{filename}" if options[:verbose]
      pom_doc = REXML::Document.new(File.read(filename))
      from_doc(pom_doc, options)
    end

    def self.from_url(url, options = {})
      uri = URI.parse(url)
      puts "Retrieving POM from #{url}" if options[:verbose]
      pom_doc = REXML::Document.new(Net::HTTP.get(uri))
      from_doc(pom_doc, options)
    end
    
    # Unless the maven version string is a valid Gem version string create a substitute
    # gem version string by dividing the maven version string into it's numeric elements
    # and joining them back together with '.' characters.
    # 
    # The string 'alpha' in a maven version string is converted to '0'.
    # The string 'beta' in a maven version string is converted to '1'.
    # 
    # In general gem versions strings need to either be an Integer or start with a 
    # digit and a '.'.
    # 
    # For example the flying saucer core-renderer jar that uses itext to generate a
    # pdf from styled xhtml input has a version string of "R8pre2". 
    # 
    # Installing this jar:
    # 
    #   jruby -S gem maven org/xhtmlrenderer core-renderer R8pre2
    # 
    # results in:
    # 
    #   Successfully installed core-renderer-8.2-java
    #   1 gem installed
    # 
    #   jruby -S gem list core-renderer
    #   
    #   *** LOCAL GEMS ***
    #   
    #   core-renderer (8.2)
    # 
    # In addition the following constants are created in the new maven gem:
    # 
    #   CoreRenderer::VERSION         # => "8.2"
    #   CoreRenderer::MAVEN_VERSION   # => "R8pre2"
    # 
    def self.maven_to_gem_version(maven_version)
      maven_version = maven_version.gsub(/alpha/, '0')
      maven_version = maven_version.gsub(/beta/, '1')
      maven_numbers = maven_version.gsub(/\D+/, '.').split('.').find_all { |i| i.length > 0 }
      if maven_numbers.empty?
        '0.0.0'
      else
        maven_numbers.join('.')
      end
    end

    def self.from_doc(pom_doc, options = {})
      begin
        spec = Gem::Specification.new

        spec.platform = "java"

        pom = parse_pom(pom_doc, options)
        spec.version = pom.version

        group_dir = pom.group.gsub('.', '/')

        spec.name = "#{pom.group}.#{pom.artifact}"
        spec.lib_files << "#{pom.artifact}.rb"
        gem_name = "#{spec.name}-#{pom.version}"
        gem_dir = "#{gem_name}.#{$$}"
        remote_dir = "#{group_dir}/#{pom.artifact}/#{pom.version}"
        jar_file = "#{gem_name}.jar"
        spec.lib_files << jar_file
        pom.dependencies.each {|dep| spec.dependencies << dep}
        spec.authors = pom.authors

        puts "Using #{gem_dir} work dir" if options[:verbose]
        FileUtils.mkdir_p(gem_dir)
        FileUtils.mkdir_p("#{gem_dir}/lib")

        full_url = "#{maven_base_url}/#{remote_dir}/#{jar_file}"
        puts "Fetching #{full_url}" if options[:verbose]
        uri = URI.parse(full_url)
        jar_contents = Net::HTTP.get(uri)
        File.open("#{gem_dir}/lib/#{jar_file}", 'w') {|f| f.write(jar_contents)}

        ruby_file_contents = <<HEREDOC
module #{pom.titleized_classname}
  VERSION = '#{pom.version}'
  MAVEN_VERSION = '#{pom.maven_version}'   
end
begin
  require 'java'
  require File.dirname(__FILE__) + '/#{jar_file}'
rescue LoadError
  puts 'JAR-based gems require JRuby to load. Please visit www.jruby.org.'
  raise
end
HEREDOC
        ruby_file = "#{gem_dir}/lib/#{pom.artifact}.rb"
        puts "Writing #{ruby_file}" if options[:verbose]
        File.open(ruby_file, 'w') do |file|
          file.write(ruby_file_contents)
        end

        metadata_file = "#{gem_dir}/metadata"
        puts "Writing #{metadata_file}" if options[:verbose]
        File.open(metadata_file, 'w') do |file|
          file.write(spec.to_yaml)
        end

        gem_file = "#{gem_name}-java.gem"

        puts "Building #{gem_file}" if options[:verbose]
        Dir.chdir(gem_dir) do
          fail unless
            system('gzip metadata') and
            system('tar czf data.tar.gz lib/*') and
            system("tar cf ../#{gem_file} data.tar.gz metadata.gz")
        end

        puts "Done!" if options[:verbose]
      ensure
        FileUtils.rm_rf(gem_dir)
      end

      "#{gem_name}-java.gem"
    end

    def self.maven_base_url
      "http://mirrors.ibiblio.org/pub/mirrors/maven2"
    end

    def self.parse_pom(pom_doc, options = {})
      pom = OpenStruct.new

      puts "Processing POM" if options[:verbose]
      pom_doc.elements.each("/project/*") do |element|
        case element.name
        when "artifactId"
          pom.artifact = element.text
          pom.titleized_classname = pom.artifact.chomp('.rb').split('-').collect { |e| e.capitalize }.join
        when "groupId"
          pom.group = element.text
        when "version"
          pom.maven_version = element.text
          pom.version = MavenGem::PomSpec.maven_to_gem_version(pom.maven_version)
        when "description"
          pom.description = element.text
        when "dependencies"
          pom.dependencies ||= []
          element.elements.each do |dependency|
            dep_group = REXML::XPath.first(dependency, 'groupId').text
            dep_artifact = REXML::XPath.first(dependency, 'artifactId').text
            dep_version = REXML::XPath.first(dependency, 'version').text

            new_dep = Gem::Dependency.new("#{dep_group}.#{dep_artifact}", "=#{dep_version}")
            pom.dependencies << new_dep
          end
        when "developers"
          pom.authors ||= []
          element.elements.each("developer") do |developer|
            pom.authors << developer.elements[2].text
          end
        when "url"
          pom.homepage = element.text
        end
      end
      pom
    end
  end
end

if __FILE__ == $0
  if ARGV[0]
    if ARGV[0] =~ %r[^http://]
      spec = MavenGem::PomSpec.from_url(ARGV[0])
    else
      spec = MavenGem::PomSpec.from_file(ARGV[0])
    end
  else
    raise ArgumentError, "specify filename or URL on command line"
  end
end
