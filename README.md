# Ceph Barclamp for OpenCrowbar #

The Ceph workload for OpenCrowbar is a fully distributed block store,
object store, and POSIX filesystem.  Ceph is designed to have no
single points of failure, and uses a unique algorithim called CRUSH to
manage data placement in the storage cluster.  Right now, this
barclamp knows how to deploy hammer on centos 7.1.1503

## Design of the Barclamp ##

This barclamp is in development, and should not be considered
production-ready.  That said, this is inteded to become a
production-ready workload.

## Adding the barclamp before deploying the admin node ##

To add this barclamp to OpenCrowbar admin node prior to deploy, follow
these instructions:

1. In /opt/opencrowbar, run the following commands:

        git clone https://github.com/opencrowbar/ceph
        cd ceph
        git checkout develop

## Using the barclamp to deploy Ceph ##

The ceph barclamp, like all other OpenCrowbar barclamp, provides most
of its functionality on a role by role basis.  Right now, we deploy
just the rados layer of ceph -- we do not handle deploying an object
gateway or a POSIX filesystem layer.  The job of deploying Ceph os
split across three roles, each described in their own section.


### ceph-config ###

The `ceph-config` role holds cluster-wide configuration information for
the Crowbar framework, and also acts as a sychronization point during
the deployment to ensure that all of the prerequisite roles have been
deployed on all nodes in the Ceph cluster before allowing the rest of
the Ceph cluster roles to do their work.

`ceph-config` holds the following pieces of cluster-wide information,
and which can be set on a per-deployment basis prior to committing the cluster
deployment:

* the `ceph-debug` attribute, which controls whether the Ceph debug
  packages will be installed and whether the various Ceph components
  will operate in debug mode.  This attribute defaults to `false`.

* the `ceph-fs_uuid` attribute, which contains the UUID of the
  cluster.  This attribute is automatically generated the first time
  the `ceph-config` role is bound to a deployment, so you do not need
  to create it manually.

* the `ceph-cluster_name` attribute, which contains the name of the
  cluster.  This attribute defaults to `ceph`.

* the `ceph-frontend-net` attribute, which contains the name of the
  Crowbar managed network that the Ceph cluster should use to
  communicate with the outside world.  This network must be created
  before trying to bind the `ceph-config` role to a node, otherwise
  the binding will fail.  Creating the network will allow the binding
  to succeed.  Defaults to `ceph`.

* the `ceph-backend-net` attribute, which contains the name of the
  Crowbar managed network that the Ceph cluster will use for internal
  communication.  It follows the same rules as the `ceph-frontend-net`
  attribute.  If it is set to the same value as the
  `ceph-frontend-net`, then just the frontend net will be used.
  Defaults to `ceph`.

`ceph-config` also defines a couple of node-specific attributes:

* `ceph-frontend-address`, which holds the Crowbar-assigned IP address
  for the frontend network.  This attribute is configured internally
  by `ceph-config` role, and cannot be manually edited.

* `ceph-backend-address`, which holds the Crowbar-assigned IP address
  for the backend network.  It is also configured internally by the
  `ceph-config` role, and cannot be manually edited.

The `ceph-config`role implements the `on_node_bind` hook, which is
used to ensure that the `crowbar-frontend-net` and
`crowbar-backend-net` networks are bound to the node before the
`ceph-config` role can successfully bind to the node.

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

The `ceph-mon` role provides the following attributes, all of which
are automatically generated:

* `ceph-mon_secret`, which contains the shared secret that the
  monitors use to validate and talk to each other.  This secret is
  automatically generated then the role is bound to a deployment.

* `ceph-mon-nodes`, which contains the complete list of all nodes and
  their addresses that will act as monitors.  This list is dynamically
  generated, and will change as new nodes are bound to the ceph-mon
  role.

* `ceph-admin-key`, which contains the secret key that grands admin
  access to the cluster.  The key this attribute contains is generated
  the first time the ceph-mon nodes reach consensus.

* `ceph-osd-key`, which contains the secret key that OSDs will use to
  talk to the mons.  It is also automatically generated the first time
  the ceph-mon nodes reach consensus.

* `ceph-mds-key`, which contains the secret key that the MDS servers
  will use to talk to the mons. It is also automatically generated the
  first time the ceph-mon nodes reach consensus.

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
storage on a node, and make available to the Ceph cluster.  OSDs
communicate with each other and the mons to form the core of the Ceph
cluster -- no other roles are needed for applications that talk to the
cluster directly using RADOS. Right now, the `ceph-osd` role will use
all of the disks that do not have partitions, filesystems, or LVM
metadata on them -- in the future, the `ceph-osd` role will use the
Crowbar resource reservation framework to determine what disks to use,
and will act intelligently to place journals on SSD drives where
desirable.  The `ceph-osd` role requires the `ceph-config` role and
the `ceph-mon` role.

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

## Deploying a Ceph cluster using the default settings ##

1. Spin up at least 3 nodes for Ceph.  These nodes sholuld have at
least 3 free disks each for OSDs.

2. Create a new deployment named `ceph`, and move all the nodes you
   want to participate in the Ceph cluster into it.

3. Create a network named `ceph`.  This network should have its own
nonoverlapping conduit.

4. From the CLI, run the following command to bind the ceph-mon role to at least 3 nodes:

   * `crowbar roles bind ceph-mon to <node name>`

5. From the CLI, run the following command to bind the ceph-osd roles
   to all the nodes you want to store info on:

   * `crowbar roles bind ceph-osd to <node name>`

6. Commit the deployment with `crowbar deployments commit ceph`. This
   will let Crowbar deploy everything you requested.
