"""Remix PBR AI: generate and upscale PBR textures for RTX Remix replacements.

The pipeline reads a PMX model, finds the Remix texture hashes of its
textures in a running Garry's Mod RTX session, runs AI upscaling and PBR map
generation, and publishes the result as a hot-reloadable Remix mod.
"""

__version__ = "0.1.0"
