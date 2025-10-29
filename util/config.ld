-- LDoc configuration for CC-Misc utilities
project = 'CC-Misc Utilities'
title = 'ComputerCraft Utility Library Documentation'
description = 'A collection of utility modules for ComputerCraft development'

-- Input and output
file = {'cmd.lua', 'formui.lua', 'persist.lua', 's.lua', 'tables.lua', 'timeutil.lua', 'shopk/shopk.lua'}
dir = '../docs'

-- Formatting options
format = 'discount' -- Markdown processor
style = true -- Use CSS styling
template = true -- Use templates

-- EmmyLua specific
parse_extra = {'emmylua'}

-- Examples
examples = {'../examples'}

-- Custom tags
custom_tags = {
    {'note', title='Note'},
    {'warning', title='Warning'}
}

-- Module information
topics = {
    'README.md'
}