import numpy as np
cimport numpy as np
cimport cython

from ..metrics import euclidean_distances
from .k_means_ import _tolerance
from ._k_means import _centers_dense


@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cdef d(double[:] a, double[:] b):
    cdef double result = 0
    cdef int i
    for i in range(len(a)):
        result += (a[i] - b[i]) ** 2
    return np.sqrt(result)


@cython.boundscheck(False)
@cython.wraparound(False)
@cython.cdivision(True)
cdef assign_labels(double[:, :] X, double[:, :] centers, double[:, :]
                   center_distances):
    # assigns closest center to X
    # uses triangle inequality
    new_centers, distances = [], []
    cdef double d_c, dist
    cdef int c_x
    for x in X:
        # assign first cluster center
        c_x = 0
        d_c = d(x, centers[0])
        for j, c in enumerate(centers):
            if d_c > center_distances[c_x, j]:
                dist = d(x, c)
                if dist < d_c:
                    d_c = dist
                    c_x = j
        new_centers.append(c_x)
        distances.append(d_c)
    return np.array(new_centers, dtype=np.int32), np.array(distances)


def k_means_elkan(X, n_clusters, init, float tol=1e-4, int max_iter=30, verbose=False):
    #initialize
    tol = _tolerance(X, tol)
    centers = init
    cdef int n_samples = X.shape[0]
    cdef int n_centers = centers.shape[0]
    cdef int point_index, center_index, label
    cdef float upper_bound, distance
    cdef double[:, :] center_distances = euclidean_distances(centers) / 2.
    cdef double[:, :] lower_bounds = np.zeros((n_samples, n_centers))
    labels, upper_bounds = assign_labels(
        X, centers, center_distances)
    # make bounds tight for current labelss
    for point_index in range(n_samples):
        lower_bounds[point_index, labels[point_index]] = upper_bounds[point_index]
    bounds_tight = np.ones(n_samples, dtype=np.bool)
    for iteration in range(max_iter):
        distance_next_center = np.sort(center_distances, axis=0)[1]
        points_to_update = distance_next_center[labels] < upper_bounds
        for point_index in np.where(points_to_update)[0]:
            upper_bound = upper_bounds[point_index]
            label = labels[point_index]
            # check other update conditions
            for center_index, center in enumerate(centers):
                if (center_index != label
                        and (upper_bound > lower_bounds[point_index, center_index])
                        and (upper_bound > center_distances[center_index, label])):
                    # update distance to center
                    if not bounds_tight[point_index]:
                        upper_bound = d(X[point_index], centers[label])
                        lower_bounds[point_index, label] = upper_bound
                        bounds_tight[point_index] = True
                    # check for relabels
                    if (upper_bound > lower_bounds[point_index, center_index]
                            or (upper_bound > center_distances[label, center_index])):
                        distance = d(X[point_index], center)
                        lower_bounds[point_index, center_index] = distance
                        if distance < upper_bound:
                            label = center_index
                            upper_bound = distance
            labels[point_index] = label
            upper_bounds[point_index] = upper_bound

        # compute new centers
        new_centers = _centers_dense(X, labels, n_centers, upper_bounds)
        bounds_tight = np.zeros(n_samples, dtype=np.bool)

        # compute distance each center moved
        center_shift = np.sqrt(np.sum((centers - new_centers) ** 2, axis=1))
        # update bounds accordingly
        lower_bounds = np.maximum(lower_bounds - center_shift, 0)
        upper_bounds = upper_bounds + center_shift[labels]
        # reassign centers
        centers = new_centers
        # update between-center distances
        center_distances = euclidean_distances(centers) / 2.
        if verbose:
            print('Iteration %i, inertia %s'
                  % (iteration, np.sum((X - centers[labels]) ** 2)))

        if np.sum(center_shift) < tol:
            print("center shift within tolerance")
            break
    return centers, labels
