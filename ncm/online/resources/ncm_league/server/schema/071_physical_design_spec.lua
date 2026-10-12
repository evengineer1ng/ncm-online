-- Persist the full, immutable physics specification for dynamically researched Designs.
NcmSchema=NcmSchema or {}
NcmSchema[#NcmSchema+1]={version=71,name="physical_design_spec",statements={
[[ALTER TABLE component_design ADD COLUMN spec_json MEDIUMTEXT NULL]],
}}
