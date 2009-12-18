require 'rubygems/command_manager'
require 'rubygems/remote_fetcher'
require 'rubygems/spec_fetcher'

Gem::CommandManager.instance.register_command :maven

Gem::SpecFetcher.class_eval do
  alias :fetch_old :fetch

  def fetch(dependency, all = false, matching_platform = true, prerelease = false)
    begin
      returned = fetch_old(dependency, all, matching_platform, prerelease)
      fetch_maven(dependency)
      return returned
    end
  end

  private
  def fetch_maven(dependency)
    require 'net/http'

    group, artifact, version = dependency.name.split(':')
    return unless artifact
    uri = "http://mirrors.ibiblio.org/pub/mirrors/maven2/#{group.gsub('.', '/')}/#{artifact}"
    uri += "/#{version}" if version

    uri = URI.parse(uri)
    req = Net::HTTP::Get.new(uri.path)
    response = Net::HTTP.start(uri.host, uri.port) {|http| http.request(req) }

    case response
    when Net::HTTPSuccess, Net::HTTPRedirection
      require 'rubygems'
      require 'mvn_gem'
      MavenGem.install(group, artifact, version)
    end

  end
end

Gem::RemoteFetcher.class_eval do
  alias :download_old :download

  def download(spec, source_uri, install_dir = Gem.dir)
    download_old(spec, source_uri, install_dir)
  end
end
