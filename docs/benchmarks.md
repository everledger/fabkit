# Benchmarks

The repository provides also a simple implementation of a bulk load function in order to benchmark the general speed of the network in terms of tps (transactions-per-second).

```bash
fabkit benchmark load [jobs] [entries]

# e.g.
fabkit benchmark load 5 1000
```

The example above will do a bulk load of 1000 entries times 5 parallel jobs, for a total of 5000 entries. At the completion of all the jobs it will be prompted on screen the elapsed time of the total task.

**Note: Kepe the number of jobs not higher than your CPU cores in order to obtain the best results. This implementation does not provides a complete parallelization.**

To achieve the optimal result it is recommended to install [Gnu Parallel](https://www.gnu.org/software/parallel/) and use as it follows:

```bash
parallel ./fabkit benchmark load {} ::: [entries])

# e.g.
parallel ./fabkit benchmark load {} ::: 20
# prefix with FABKIT_DEBUG=true to see more logs
```
