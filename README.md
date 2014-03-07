# Ceph Barclamp for OpenCrowbar #

The Ceph workload for OopenCrowbar is a fully distributed block
store, object store, and POSIX filesystem.  Ceph is designed to have
no single points of failure, and uses a unique algorithim called CRUSH
to manage data placement in the storage cluster.

## Design of the Barclamp ##

Like all barclamps, this one is split into several parts:

* The framework part, which is implemented as a Rails Engine that
  plugs into a running Crowbar admin node.
* The jig part, which is responsible for effecting change on the nodes
  that you choose to be part of the cluster.
* The package archive part, which is a self-contained archive of all
  the packages that are needed to install the Ceph cluster.

This barclamp is intended to be the first demonstration workload for
Crowbar 2.0, and should not be considered production-ready.  Instead,
it serves to act as a working example of a running non-trivial
workload that can be used as an example of what is required to
implement a barclamp in Crowbar 2.0.

## Adding the barclamp during the Crowbar Build ##

To add this barclamp to the crowbar 2 build on Ubuntu 12.04, perform
the following steps:

1. At the top level Crowbar directory, run the following command:

        echo master > releases/development/master/barclamp-ceph

   This will tell the Crowbar build system that you want Ceph to be a
   part of the development/master build.  Normally, you would create a
   new build, but we are taking some shortcuts here.
2. At the top-level Crowbar directory, run the following commands:

        git clone https://github.com/VictorLowther/barclamp-ceph.git barclamps/ceph
        cd barclamps/ceph
        git submodule update --init
        git checkout master

   This will check out the apache2 and ceph cookbooks that the Ceph
   barclamp requires. The apache2 cookbook comes straight from
   <https://github.com/opscode-cookbooks/apache2.git>, and the Ceph
   cookbook is a fork of
   <https://github.com/ceph/ceph-cookbooks.git> that contains
   modifications needed to work with Crowbar 2.

Once these steps are finished, Ceph will be a part of all your Crowbar
2 builds until you undo the changes made in step 1.

## Ceph Barclamp Roles ##

One of the major differences between Crowbar 1 and Crowbar 2 is that
most configuration is handled on a role by role basis instead of a
barclamp by barclamp basis -- in Crowbar 2, barclamps exist to package
up related roles and their support infrastructure. We will take a
closer look at the crowbar.yml to see what roles it declares and to
see what roles it depends on.

Most of the sections that are in the crowbar.yml will be the same --
we still have the barclamp metadata, sections for declaring what
packages we need, and locale information.  The big thing that is new
is the roles stanza, which lets the Crowbar framework know what roles
the Ceph barclamp provides, and what other roles those roles require.
The roles section of the crowbar.yml looks like this:

    roles:
      - name: ceph-config
        jig: noop
        requires:
          - network-ceph
          - crowbar-installed-node
        flags:
          - implicit
          - cluster
      - name: ceph-mon
        jig: chef
        requires:
          - ceph-config
        flags:
          - cluster
          - server
      - name: ceph-osd
        jig: chef
        requires:
          - ceph-config
          - ceph-mon
      - name: ceph-radosgw
        jig: chef
        requires:
          - ceph-config
          - ceph-mon
          - ceph-osd
      - name: ceph-mds
        jig: chef
        requires:
          - ceph-config
          - ceph-mon
          - ceph-osd
      - name: ceph-client
        jig: chef
        requires:
          - ceph-config
          - ceph-mon
          - ceph-osd

From this, we can see that that Ceph barclamp provides 6 roles named
`ceph-config`, `ceph-mon`, `ceph-osd`, `ceph-radosgw`, `ceph-mds`, and
`ceph-client`, and that those roles depend on each other and on 2 roles
that are not part of the Ceph barclamp: `network-ceph`, and
`crowbar-installed-node`.

### ceph-config ###

The `ceph-config` role holds cluster-wide configuration information for
the Crowbar framework, and also acts as a sychronization point during
the deployment to ensure that all of the prerequisite roles have been
deployed on all nodes in the Ceph cluster before allowing the rest of
the Ceph cluster roles to do their work.

The only piece of the cluster-wide configuration information that the
`ceph-config` role needs to provide is a UUID for the Ceph filesystem.
This gets generated when the deployment role for the cluster is
generated.  To do that, we provide a role-specific override for the
`ceph-config` role by creating a `BarclampCeph::Config` class as a
subclass of the Role class, and declaring an `on_deployment_create`
method in that class that creates a new UUID for the cluster.

You may have noticed that every other ceph role requires the
`ceph-config` role, and that the `ceph-config` role has an implicit flag
and a cluster flag.  The implicit flag tells that Crowbar framework
that this role must be bound to the same node that its direct children
are bound to -- this forces the `ceph-config` role to be present on all
nodes that participate in the Ceph cluster.  The cluster flag tells
the Crowbar framework that it should ensure that all of the child
noderoles for the service are bound to all of the noderoles for the
role in question.  This forces the annealer to ensure that all of the
`ceph-config` noderoles have transitioned to active before allowing any
noderoles that directly depend on `ceph-config` to transition to todo.
Since `ceph-config` requires `network-ceph` and `crowbar-installed-node`,
this effectively forces all nodes in the cluster to have their
operating systems installed and to be on the ceph network before
allowing the rest of the deployment to continue.

### ceph-mon ###

The `ceph-mon` role implements a Ceph monitor service on a node.  All of the
Ceph monitors together form a paxos cluster that the rest of the Ceph
services use to track the overall state of the cluster -- as long as a
majority of the `ceph-mon` nodes are up, then the ceph cluster is
alive.  As such, you should deploy `ceph-mon` on at least 3 nodes, and you
should always have an odd number of them.

Since the `ceph-mon` role requires the `ceph-config` role, the annealer
will wait until all the `ceph-config` noderoles in the deployment are
active before starting to activate the `ceph-mon` roles.  We need this
behaviour to pass a list of all the `ceph-mon` nodes and their addresses
in the ceph network to the other `ceph-mon` nodes to let the cluster
form its initial quorum when we are bringing the cluster up for the
first time.  The `ceph-mon` role also needs to generate a random secret
key that all the `ceph-mon` noderoles will share.  To implement both
behaviours, the Ceph barclamp provides a `BarclampCeph::Mon` class
that inherits from the `Role` class.  The `BarclampCeph::Mon` class
implements two methods -- an `on_deployment_create` method that
creates the initial mon secret key, and a `sysdata` method that
provides a hash containing all of the monitors that are a member of
the cluster.

The `ceph-mon` role also has two flags -- the cluster flag, which we use
to ensure that the annealer will not start working on the rest of the
Ceph noderoles until all the `ceph-mon` nodes are active (and therefore
in quorum), and the server flag, which tells the annealer that any
attributes that the recipe sets should be made available to its
children.  We will need that to get the secret keys for the cluster
administrator, and the keys needed to bootstrap storage and MDS roles.

The `ceph-mon` role is implemented using the chef jig.

### ceph-osd ###

The `ceph-osd` role implements causes Ceph to claim all available
storage on a node, and make available to the Ceph cluster.  OSDs communicate
with each other and the mons to form the core of the Ceph cluster --
no other roles are needed for applications that talk to the cluster
directly using RADOS. Right now, the `ceph-osd` role will use all of the
disks that do not have partitions, filesystems, or LVM metadata on
them -- in the future, the `ceph-osd` role will use the
yet-to-be-written Crowbar resource reservation framework to determine
what disks to use.  The `ceph-osd` role requires the `ceph-config` role
and the `ceph-mon` role.

### ceph-mds ###

The `ceph-mds` role implements a metadata service for the Ceph cluster,
which implements a distributed POSIX filesystem on top of the ceph
cluster.

### ceph-radosgw ###

The `ceph-radosgw` role allows external users to access the Ceph cluster
as an object store using S3 and Swift APIs.

### ceph-client ###

The `ceph-client` role should be bound to any node that wants to access
the Ceph cluster, although it has not been fleshed out to add any
functionality.  It may be removed if it does not prove to be useful,
or if it turns out that we need multiple different types of clients.

## Design limitations of the Ceph barclamp ##

Right now, the Crowbar 2.0 Ceph barclamp is not production-ready, and
there are a few things that would be needed to make it production
ready:

* Improved network configuration.  Right now, the Ceph roles rely
  explicitly on having a dedicated Ceph network that all of the Ceph
  roles communicate over, the recipes assume that we want to use the
  autmatically-assigned IPv6 addresses in the ceph network, and anyone
  that wants to communicate with the cluster needs to have an IPv6
  address in that range.  To be used in production, we will probably
  want a dedicated ceph storage network for backend communication
  amongst the OSDs, and a seperate ceph public network for the mon,
  mds, radosgw, and client nodes, and the frontend network should
  probably talk IPv4.
* Configration and performance tuning options.  Right now, we
  confugure the bare minimum needed to allow the cluster to
  come up and talk over IPv6, and use the defaults for everything
  else.  The defaults are not suitable for a production cluster.
