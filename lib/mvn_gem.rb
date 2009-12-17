require 'net/http'
require 'pom2gem'
require 'rubygems/gem_runner'

module MavenGem
  def MavenGem.install(group, artifact = nil, version = nil)
    begin
      gem = build(group, artifact, version)
      Gem::GemRunner.new.run(["install", gem])
    ensure
      FileUtils.rm_f gem
    end
  end

  def MavenGem.build(group, artifact = nil, version = nil)
    gem = if artifact
      # fetch pom and install
      url = MavenGem::PomSpec.maven_base_url + "/#{group}/#{artifact}/#{version}/#{artifact}-#{version}.pom"
      PomSpec.from_url(url)
    else
      if group =~ %r[^http://]
        PomSpec.from_url(group)
      else
        PomSpec.from_file(group)
      end
    end
  end
end
