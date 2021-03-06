# This file is part of the Juju GUI, which lets users view and manage Juju
# environments within a graphical interface (https://launchpad.net/juju-gui).
# Copyright (C) 2013 Canonical Ltd.
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License version 3, as published by
# the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranties of MERCHANTABILITY,
# SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

"""Bundle deployment utility functions and objects."""

import collections
from functools import wraps
import itertools
import logging
import time

from tornado import (
    gen,
    escape,
)

from guiserver.watchers import AsyncWatcher


# Change statuses.
SCHEDULED = 'scheduled'
STARTED = 'started'
CANCELLED = 'cancelled'
COMPLETED = 'completed'
# Define a sequence of allowed constraints to be used in the process of
# preparing the bundle object. See the _prepare_constraints function below.
ALLOWED_CONSTRAINTS = ('arch', 'cpu-cores', 'cpu-power', 'mem')


def create_change(deployment_id, status, queue=None, error=None):
    """Return a dict representing a deployment change.

    The resulting dict contains at least the following fields:
      - DeploymentId: the deployment identifier;
      - Status: the deployment's current status;
      - Time: the time in seconds since the epoch as an int.

    These optional fields can also be present:
      - Queue: the deployment position in the queue at the time of this change;
      - Error: a message describing an error occurred during the deployment.
    """
    result = {
        'DeploymentId': deployment_id,
        'Status': status,
        'Time': int(time.time()),
    }
    if queue is not None:
        result['Queue'] = queue
    if error is not None:
        result['Error'] = error
    return result


class Observer(object):
    """Handle multiple deployment watchers."""

    def __init__(self):
        # Map deployment identifiers to watchers.
        self.deployments = {}
        # Map watcher identifiers to deployment identifiers.
        self.watchers = {}
        # This counter is used to generate deployment identifiers.
        self._deployment_counter = itertools.count()
        # This counter is used to generate watcher identifiers.
        self._watcher_counter = itertools.count()

    def add_deployment(self):
        """Start observing a deployment.

        Generate a deployment id and add it to self.deployments.
        Return the generated deployment id.
        """
        deployment_id = self._deployment_counter.next()
        self.deployments[deployment_id] = AsyncWatcher()
        return deployment_id

    def add_watcher(self, deployment_id):
        """Return a new watcher id for the given deployment id.

        Also add the generated watcher id to self.watchers.
        """
        watcher_id = self._watcher_counter.next()
        self.watchers[watcher_id] = deployment_id
        return watcher_id

    def notify_position(self, deployment_id, position):
        """Add a change to the deployment watcher notifying a new position.

        If the position in the queue is 0, it means the deployment is started
        or about to start. Therefore set its status to STARTED.
        """
        watcher = self.deployments[deployment_id]
        status = SCHEDULED if position else STARTED
        change = create_change(deployment_id, status, queue=position)
        watcher.put(change)

    def notify_cancelled(self, deployment_id):
        """Add a change to the deployment watcher notifying it is cancelled."""
        watcher = self.deployments[deployment_id]
        change = create_change(deployment_id, CANCELLED)
        watcher.close(change)

    def notify_completed(self, deployment_id, error=None):
        """Add a change to the deployment watcher notifying it is completed."""
        watcher = self.deployments[deployment_id]
        change = create_change(deployment_id, COMPLETED, error=error)
        watcher.close(change)


def _prepare_constraints(constraints):
    """Validate and prepare the given service constraints.

    If constraints are passed as a string, convert them to be a dict.

    Return the validated constraints dict.
    Raise a ValueError if unsupported constraints are present.
    """
    if not isinstance(constraints, collections.Mapping):
        try:
            constraints = dict(i.split('=') for i in constraints.split(','))
        except ValueError:
            # A ValueError is raised if constraints are invalid, e.g. "cpu=,".
            raise ValueError('invalid constraints: {}'.format(constraints))
    unsupported = set(constraints).difference(ALLOWED_CONSTRAINTS)
    if unsupported:
        msg = 'unsupported constraints: {}'.format(
            ', '.join(sorted(unsupported)))
        raise ValueError(msg)
    return constraints


def prepare_bundle(bundle):
    """Validate and prepare the bundle.

    In particular, convert the service constraints, if they are present and if
    they are represented as a string, to a dict, as expected by the deployer.

    Modify in place the given YAML decoded bundle dictionary.
    Return None if everything is ok.
    Raise a ValueError if:
        - the bundle is not well structured;
        - the bundle does not include services;
        - the bundle includes unsupported constraints.
    """
    # XXX frankban 2013-11-07: is the GUI Server in charge of validating the
    # bundles? For now, the weak checks below should be enough.
    if not isinstance(bundle, collections.Mapping):
        raise ValueError('the bundle data is not well formed')
    services = bundle.get('services')
    if not isinstance(services, collections.Mapping):
        raise ValueError('the bundle does not contain any services')
    # Handle services' constraints.
    for service_data in services.values():
        if 'constraints' in service_data:
            constraints = service_data['constraints']
            if not constraints:
                # If constraints is an empty string, just delete the key.
                del service_data['constraints']
            else:
                # Otherwise sanitize the value.
                service_data['constraints'] = _prepare_constraints(constraints)


def require_authenticated_user(view):
    """Require the user to be authenticated when executing the decorated view.

    This function can be used to decorate bundle views. Each view receives
    a request and a deployer, and the user instance is stored in request.user.
    If the user is not authenticated an error response is raised when calling
    the view. Otherwise, the view is executed normally.
    """
    @wraps(view)
    def decorated(request, deployer):
        if not request.user.is_authenticated:
            raise response(error='unauthorized access: no user logged in')
        return view(request, deployer)
    return decorated


def response(info=None, error=None):
    """Create a response containing the given (optional) info and error values.

    This function is intended to be used by bundles views.
    Return a gen.Return instance, so that the result of this method can easily
    be raised from coroutines.
    """
    if info is None:
        info = {}
    data = {'Response': info}
    if error is not None:
        logging.error('deployer: {}'.format(escape.utf8(error)))
        data['Error'] = error
    return gen.Return(data)
