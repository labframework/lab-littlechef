# perhaps these should just be put in the runlist instead??

package "python-software-properties"
package "tree"

include_recipe "java"

# https://launchpad.net/ubuntu/precise/amd64/openjdk-6-jdk
package "openjdk-6-jdk" do
  action :install
  version "6b27-1.12.6-1ubuntu0.12.04.2"
end

package "libicu-dev" do
  action :install
end

# we need this concord maven provider to resolve
# some legacy artifacts used by otrunk

directory "/home/deploy/.m2" do
  owner "deploy"
  group "root"
  mode "0755"
  action :create
end

cookbook_file "/home/deploy/.m2/settings.xml" do
  source "settings.xml"
  owner "deploy"
  group "root"
  mode "664"
end

# add the node repository here so we can make sure that apt-get update runs correctly
# https://launchpad.net/~chris-lea/+archive/node.js/
apt_repository 'node.js' do
  uri 'http://ppa.launchpad.net/chris-lea/node.js/ubuntu'
  distribution node['lsb']['codename']
  components ['main']
  keyserver "keyserver.ubuntu.com"
  key "C7917B12"
  action :add
end

# ppa for the couchdb repository
# https://launchpad.net/~longsleep/+archive/couchdb
# apt_repository 'couchdb' do
#   uri 'http://ppa.launchpad.net/longsleep/couchdb/ubuntu'
#   distribution node['lsb']['codename']
#   components ['main']
#   keyserver "keyserver.ubuntu.com"
#   key "56A3D45E "
#   action :add
# end

# the apt_repository tries to do this itself, but it isn't using
# the root user so it seems to fail
execute "apt-get update" do
  action :run
  user "root"
end

include_recipe "apache2"

package "apache2" do
  action :install
  # version "2.2.22-1ubuntu1.3"
end

# include_recipe "nodejs"
# installing nodejs now also installs npm
package "nodejs" do
  action :install
  action :upgrade
end

# package "couchdb" do
#   action :install
#   version "1.2.1-0ppa1+0"
# end

# the couchdb service script creates this folder but does so as root
# instead of the couchdb user
# directory "/var/run/couchdb" do
#   owner "couchdb"
#   group "root"
#   mode "755"
# end

directory "/var/www" do
  owner "deploy"
  group "root"
  mode "755"
end

directory "/var/www/log" do
  owner "www-data"
  group "www-data"
  mode "755"
end

script "update_npm" do
  interpreter "bash"
  user "deploy"
  code "sudo npm update -g npm"
end

script "setup_coffee" do
  interpreter "bash"
  user "deploy"
  code "sudo npm install -g coffee-script"
end

# service "couchdb" do
#   action :start
# end

group "rvm" do
  append true
  members ["deploy", "ubuntu"]
end

cookbook_file "/home/deploy/.rvmrc" do
  source "rvmrc"
  owner "deploy"
  group "deploy"
  mode "664"
end

cookbook_file "/home/deploy/.bash_login" do
  source "dot_bash_login"
  owner "deploy"
  group "deploy"
  mode "664"
end

execute "enable the locate database" do
  command "sudo updatedb"
end

execute "enable access to a default locale" do
  command "sudo locale-gen en_US"
end

# Clone Lab framework with embedded web application
git "/var/www/app" do
  user "deploy"
  group "root"
  repository "git://github.com/labframework/lab.git"
  action :sync
end

# Create tmp dir in web app so Passenger restarts work by touching tmp/restart.txt
directory "/var/www/app/tmp" do
  owner "deploy"
  group "root"
  mode "775"
end

execute "configure bundler to skip installation of gems in development group" do
  user "deploy"
  cwd "/var/www/app"
  environment (
    {
      "PATH" => "PATH=/usr/local/rvm/gems/ruby-2.0.0-p247@lab/bin:/usr/local/rvm/gems/ruby-2.0.0-p247@global/bin:/usr/local/rvm/rubies/ruby-2.0.0-p247/bin:/usr/local/rvm/bin:/usr/local/maven-3.0.5/bin:/usr/local/sbin:/usr/local/bin:/usr/bin",
      "GEM_PATH" => "/usr/local/rvm/gems/ruby-2.0.0-p247@lab:/usr/local/rvm/gems/ruby-2.0.0-p247@global",
      "RUBY_VERSION" => "ruby-2.0.0-p247"
    }
  )
  command "bundle config --local without development"
end

execute "fix-permissions" do
  user "deploy"
  command <<-COMMAND
  sudo chown -R deploy:root /var/www/app/*
  sudo chown -R deploy:root /var/www/app/.[^.]*
  sudo chmod -R ug+rw /var/www/app/*
  sudo chgrp -R deploy /usr/local/rvm/*
  sudo chmod -R g+w /usr/local/rvm/*
  COMMAND
end

# create global git configuration for deploy user
template "/home/deploy/.gitconfig" do
  source "dot-gitconfig.erb"
  mode 0664
  owner "deploy"
  group "deploy"
end

if ::File.exist?("/var/www/app/config/config.yml")
  puts "config/config.yml exists"
else
  ruby_block "Creating default config/config.yml" do
   block do
    ::FileUtils.cp "/var/www/app/config/config.sample.yml", "/var/www/app/config/config.yml"
    ::FileUtils.chown 'deploy', 'root', "/var/www/app/config/config.yml"
   end
  end
end

link "/usr/local/bin/mvn" do
  to "/usr/local/maven-3.0.5/bin/mvn"
end

# execute "disable-default-apache2-site" do
#   command "sudo a2dissite default"
#   notifies :reload, resources(:service => "apache2"), :delayed
# end

web_app "lab" do
  cookbook "apache2"
  server_name node['lab-hostname']
  server_aliases [node['lab-hostname']]
  docroot "/var/www/app/public"
  enable true
  notifies :restart, resources(:service => "apache2"), :delayed
end
