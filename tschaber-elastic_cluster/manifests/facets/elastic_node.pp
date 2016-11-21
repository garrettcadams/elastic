#
#
# this file performs the installation of an
# elasticsearch master node. it will install the
# node itself including the marvel agent (which
# collects data for marvel) and the licence
# plugin. the node will be named "servername-es-01".
#
# author: Tobias Schaber (codecentric AG)
#
class elastic_cluster::facets::elastic_node(

    $collectd_config = undef,
    $elk_authentication = undef,


) {
    $install_collectd = $collectd_config['collectd_install']

    # read the complete elk configuration array
    $elk_config     = hiera('elasticsearch::config')

    # if there is a "shield" part in the configuration
    if($elk_config['xpack']) {
        $enablessl      = $elk_config['xpack']['security']['transport.ssl.enabled']
        $enablehttps    = $elk_config['xpack']['http.ssl']
    } else {
        # if there is no xpack part, disable ssl and https
        $enablessl      = false
        $enablehttps    = false
    }


    # adjust global nproc limits on RHEL, only if the 90-nproc file exist
    exec { 'increase-global-nproc-on-RHEL':
        user    => 'root',
        command => "sed -i \"s/1024/4096/g\" /etc/security/limits.d/90-nproc.conf",
        path    => ['/usr/sbin/', '/bin/', '/sbin/', '/usr/bin'],
        onlyif  => 'ls /etc/security/limits.d/90-nproc.conf',
    } ->

    # start the installation of elasticsearch
    class { 'elasticsearch' :
        ensure => present,
        status => enabled,
    } ->

        # add the default admin user
    class { 'elastic_cluster::facets::elastic_node::createadminuser' :
        enable_elk_auth   => $elk_authentication['enable_authentication'],
        defaultadmin_name => $elk_authentication['username'],
        defaultadmin_pass => $elk_authentication['password'],
    } ->

    class { 'elastic_cluster::facets::elastic_node::addkeystores' :
        enablessl   => $enablessl,
        enablehttps => $enablehttps,
    }


    # install collectd if configured
    if($install_collectd == true) {

        $collectd_servers       = $collectd_config['collectd_servers']
        $collectd_plugin_conf   = $collectd_config['collectd_plugins']
        $collectd_plugin_ignore = $collectd_plugin_conf['interface']['ignore']
        $collectd_version       = $collectd_config['collectd_version']

        # with RedHat/CentOS, the "enterprise packages" are required.
        if($::operatingsystem in ['RedHat', 'CentOS']) {
            # enterprise packages are required for installation
            package { 'epel-release':
                ensure => installed,
            } ->
            # install collect.d
            class { '::collectd':
                package_ensure  => installed,
                purge           => true,
                recurse         => true,
                purge_config    => true,
                minimum_version => $collectd_version,
            }
        } else {

            # install collect.d
            class { '::collectd':
                package_ensure  => installed,
                purge           => true,
                recurse         => true,
                purge_config    => true,
                minimum_version => $collectd_version,
            }
        }



        # add the collect.d memory plugin
        class { 'collectd::plugin::memory':
        }

        # add the collect.d cpu plugin
        class { 'collectd::plugin::cpu':
            reportbystate    => true,
            reportbycpu      => true,
            valuespercentage => true,
        }

        class { 'collectd::plugin::disk':
            disks          => ['/^dm/'],
            ignoreselected => true,
            udevnameattr   => 'DM_NAME',
        }

        class { 'collectd::plugin::uptime':
        }

        class { 'collectd::plugin::netlink':
            interfaces        => ['enp0s3'],
            verboseinterfaces => ['enp0s3'],
            qdiscs            => ['"enp0s3" "pfifo_fast-1:0"'],
            classes           => ['"enp0s3" "htb-1:10"'],
            filters           => ['"enp0s3" "u32-1:0"'],
            ignoreselected    => false,
        }

        # add the collect.d network interface plugin
        class { 'collectd::plugin::interface':
            interfaces     => $collectd_plugin_ignore,
            ignoreselected => true,
        }

        # add the collect.d network plugin and configure it to send to logstash
        class { 'collectd::plugin::network':
            timetolive    => '70',
            maxpacketsize => '42',
            forward       => true,
            reportstats   => true,
            servers       => $collectd_servers,
        }
    }
}

# install the required jks trust- and keystores
class elastic_cluster::facets::elastic_node::addkeystores(
    $enablessl = false,
    $enablehttps = false,
    $ownhost = inline_template("<%= scope.lookupvar('::hostname') -%>"),
    $elk_user = hiera('elasticsearch::elasticsearch_user', 'elasticsearch'),
    $elk_group = hiera('elasticsearch::elasticsearch_group', 'elasticsearch'),
) {

    # check if truststore is needed
    if($enablehttps == true or $enablessl == true) {
        $ensurejks = present
    } else {
        $ensurejks = absent
    }

#    if($ensurejks == 'present') {
#        file { '/etc/elasticsearch/es-01/shield' :
#            ensure => 'directory',
#            owner  => $elk_user,
#            group  => $elk_group,
#        }
#    }

    # add jks keystore
    file { '/etc/elasticsearch/es-01/shield/es01-keystore.jks' :
        ensure => $ensurejks,
        source => "/tmp/elkinstalldir/ssl/${ownhost}-keystore.jks",
        owner  => $elk_user,
        group  => $elk_group,
        mode   => '0755',
    } ->

        # add jks truststore
    file { '/etc/elasticsearch/es-01/shield/es01-truststore.jks' :
        ensure => $ensurejks,
        source => '/tmp/elkinstalldir/ssl/truststore.jks',
        owner  => $elk_user,
        group  => $elk_group,
        mode   => '0755',
    }
}


# addition class to add the default admin user to the es configuration
class elastic_cluster::facets::elastic_node::createadminuser(
    $defaultadmin_name = 'esadmin',
    $defaultadmin_pass = 'esadmin',
    $enable_elk_auth = false,
) {


    if($enable_elk_auth == true) {

        # TODO: SEEMS NOT TO WORK AS SERVICE IS NOT YET AVAILABLE!
        # create an admin user
#        exec { 'xpack-create-esadmin':
#            user    => 'root',
#            command => "curl --insecure -XPUT -u elastic:changeme 'https://localhost:9200/_xpack/security/user/${defaultadmin_name}' -d '{ \"password\" : \"${defaultadmin_pass}\", \"roles\" : [\"superuser\"]}'",
#            onlyif  => 'curl --insecure -u elastic:changeme https://localhost:9200/_xpack',
#           command => "/usr/share/elasticsearch/bin/shield/esusers useradd ${defaultadmin_name} -p ${defaultadmin_pass} -r admin",
#            unless  => "/usr/share/elasticsearch/bin/shield/esusers list | grep -c ${defaultadmin_name}",
#            path    => ['/usr/sbin/', '/bin/', '/sbin/', '/usr/bin'],
#        }

#        ->
#            # workarround: copy esuser files into elasticsearch config directory to be found
#        exec { 'copy-esuser-files-into-elk-config-dir':
#            user    => hiera('elasticsearch::elasticsearch_user', 'elasticsearch'),
#            command => 'cp -r /etc/elasticsearch/shield /etc/elasticsearch/es-01',
#            path    => ['/usr/sbin/', '/bin/', '/sbin/', '/usr/bin'],
#        }
    }
}


