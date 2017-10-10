export MachOSection, MachOSections, MachOSectionRef

"""
    MachOSection

Mach-O `Section` type, containing information about the section name, segment
name, size, address, etc... of the `Section.`
"""
abstract type MachOSection{H <: MachOHandle} <: Section{H} end
@io immutable MachOSection32{H <: MachOHandle} <: MachOSection{H}
    sectname::fixed_string{UInt128}
    segname::fixed_string{UInt128}
    addr::UInt32
    size::UInt32
    offset::UInt32
    align::UInt32
    reloff::UInt32
    nreloc::UInt32
    flags::UInt32
    reserved1::UInt32
    reserved2::UInt32
end

@io immutable MachOSection64{H <: MachOHandle} <: MachOSection{H}
    sectname::fixed_string{UInt128}
    segname::fixed_string{UInt128}
    addr::UInt64
    size::UInt64
    offset::UInt32
    align::UInt32
    reloff::UInt32
    nreloc::UInt32
    flags::UInt32
    reserved1::UInt32
    reserved2::UInt32
end

function read(oh::MachOHandle, ::Type{ST}) where {ST <: MachOSection}
    type_func = section_header_type
    size_func = section_header_size
    return read_struct(oh, type_func, size_func, "Section Header")
end


section_name(s::MachOSection) = "$(s.segname),$(s.sectname)"
section_size(s::MachOSection) = s.size
section_offset(s::MachOSection) = s.offset
section_address(s::MachOSection) = s.addr
is64bit(s::MachOSection) = isa(s, MachOSection64)


"""
    MachOSections

Mach-O `Section` object collection type.  Mach-O sections are split out over
multiple segments, one per load command.  As an example, most executables have
at least two segments, `__DATA` and `__TEXT`, each of which have multiple
sections embedded within them.  A `MachOSections` object is created from
multiple segments (in this case, realized as multiple load commands) which
contain the necessary sections, and these sections can then be accessed as
desired.
"""
immutable MachOSections{H <: MachOHandle, S <: MachOSection} <: Sections{H}
    handle::H
    sections::Vector{S}
end

# Special section_header_type() overrides for segments:
section_header_type(::MachOSegment32Cmd) = MachOSection32
section_header_type(::MachOSegment64Cmd) = MachOSection64
section_header_type(seg::MachOSegment) = section_header_type(MachOLoadCmd(seg))
@derefmethod section_header_type(seg::MachOSegmentRef)

function MachOSections(segs::MachOSegments)
    oh = handle(segs)

    # Now, load the sections off of each segment:
    sections = Any[]
    for seg in segs
        # Seek to the beginning of the section headers for this segment
        seg_size = packed_sizeof(typeof(MachOLoadCmd(deref(seg))))
        sections_pos = position(MachOLoadCmdRef(seg)) + seg_size
        seek(oh, sections_pos)

        # For each section header, read it in:
        for sect_idx in 1:segment_num_sections(seg)
            sect = read(oh, section_header_type(seg))
            push!(sections, sect)
        end
    end

    # Re-run type inference on this array, so it packs nicely
    sections = [s for s in sections]

    # Bake'em away, Toys!
    return MachOSections(oh, sections)
end

handle(sections::MachOSections) = sections.handle
endof(sections::MachOSections) = endof(sections.sections)
getindex(sections::MachOSections, idx) = getindex(sections.sections, idx)

Sections(segs::MachOSegments) = MachOSections(segs)
Sections(oh::MachOHandle) = Sections(Segments(oh))

"""
    MachOSectionRef

Mach-O `SectionRef` type
"""
immutable MachOSectionRef{H <: MachOHandle} <: Sections{H}
    sections::MachOSections{H}
    section::MachOSection{H}
    idx::UInt32
end

function SectionRef(sections::MachOSections, s::MachOSection, idx)
    return MachOSectionRef(sections, s, UInt32(idx))
end
@derefmethod is64bit(s::MachOSectionRef)

# Printing
function show(io::IO, section::Union{MachOSection,MachOSectionRef})
    print(io, "MachO Section", is64bit(section) ? " (64 bit)": "")

    if !get(io, :compact, false)
        println(io)
        println(io, "       Name: $(section_name(section))")
        println(io, "       Size: 0x$(hex(section_size(section)))")
        println(io, "     Offset: 0x$(hex(section_offset(section)))")
        print(io,   "    Address: 0x$(hex(section_address(section)))")
    else
        print(io, " \"$(section_name(section))\"")
    end
end

function show(io::IO, sects::MachOSections)
    print(io, "MachO Sections")
    for sect in sects
        print(io, "\n  ")
        showcompact(io, sect)
    end
end