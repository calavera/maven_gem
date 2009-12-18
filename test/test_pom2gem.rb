require 'test/unit'
require 'rexml/document'
require File.dirname(__FILE__) + '/../lib/pom2gem.rb'

class TestPom2Gem < Test::Unit::TestCase

POM_FILE = %q{<project>
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>org.apache</groupId>
    <artifactId>apache</artifactId>
    <version>4</version>
  </parent>
  <groupId>ant</groupId>
  <artifactId>ant</artifactId>
  <version>1.6.5</version>
  <!-- Fixed per MEV-531 -->
  <dependencies>
    <dependency>
      <groupId>xerces</groupId>
      <artifactId>xercesImpl</artifactId>
      <version>2.6.2</version>
      <optional>true</optional>
    </dependency>
    <dependency>
      <groupId>xml-apis</groupId>
      <artifactId>xml-apis</artifactId>
      <version>1.3.04</version>
      <optional>true</optional>
    </dependency>
  </dependencies>
</project>}

  def test_parse_pom_from_file
    pom = MavenGem::PomSpec::parse_pom(REXML::Document.new(POM_FILE))

    assert_equal 'ant', pom.group
    assert_equal 'ant', pom.artifact
    assert_equal '1.6.5', pom.version
    assert_equal 2, pom.dependencies.size

    assert_equal 'xerces.xercesImpl', pom.dependencies[0].name
  end

  def test_from_file
    gem = nil
    assert_nothing_raised {
      gem = MavenGem::PomSpec::from_file(File.dirname(__FILE__) + '/fixtures/ant.pom')
    }
    assert_equal 'ant.ant-1.6.5-java.gem', gem
  end
end
