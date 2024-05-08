# Kleaf Canary

Setting `--config=canary` opts into future features of Kleaf and the DDK. Think
of it as beta version where the Kleaf team enables features for early adopters
that _should be ok_ to use, but not yet for production.

Some of the features are experimental, most of them will be default in future
releases and some of them might get discontinued.

As of now, `--config=canary` enables:
 - `--toolchain_from_sources`: Build (some) build time dependencies from
     sources, like `toybox`.

