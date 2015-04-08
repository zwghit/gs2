# A file for generating overrides.f90
# To run:
#   ruby overrides.rb overrides.f90
#
# This is free software released under the MIT license
# Written by:
#           Edmund Highcock (edmundhighcock@users.sourceforge.net)
#

class Generator
  def self.generate_type(name, parameter_list)
    return <<EOF
  type #{name}_overrides_type
    !> DO NOT manually set the value of init.
    !! Nasty things may happen.
    logical :: init = .false.
    #{parameter_list.map{|p| p.switch}.join("\n    ")}
    #{parameter_list.map{|p| p.value}.join("\n    ")}
    #{name == 'optimisations' ? "integer :: old_comm" : ""}
  end type #{name}_overrides_type

EOF
  end
  def self.generate_initialize(name, parameter_list)
    return <<EOF
  #{ 
  if countpar = parameter_list.find{|p| p.count}
   "subroutine init_#{name}_overrides(overrides_obj, #{countpar.count})
    integer, intent(in) :: #{countpar.count}"
  else
   "subroutine init_#{name}_overrides(overrides_obj)"
  end}
    type(#{name}_overrides_type), intent(inout) :: overrides_obj
    if (overrides_obj%init) return 
    overrides_obj%init = .true.
    #{parameter_list.map{|p| p.init}.join("\n    ")}
  end subroutine init_#{name}_overrides

EOF
  end
  def self.generate_finish(name, parameter_list)
    return <<EOF
  subroutine finish_#{name}_overrides(overrides_obj)
    type(#{name}_overrides_type), intent(inout) :: overrides_obj
    if (.not. overrides_obj%init) then
      write (*,*) "ERROR: Called finish_#{name}_overrides on an uninitialized object"
      return
    end if
    overrides_obj%init = .false.
    #{parameter_list.map{|p| p.finish}.join("\n    ")}
  end subroutine finish_#{name}_overrides

EOF
  end

  def switch
    if @count
      "logical, dimension(:), pointer :: override_#@name"
    else
      "logical :: override_#@name"
    end
  end

  def value
    if @count
      "#@type, dimension(:), pointer :: #@name"
    else
      "#@type :: #@name"
    end
  end

  def init
    str = "overrides_obj%override_#@name = .false."
    str = "allocate(overrides_obj%override_#@name(#@count), overrides_obj%#@name(#@count))\n    " + str if @count 
    return str
  end

  def finish
    str = "overrides_obj%override_#@name = .false."
    str = str +  "\n    deallocate(overrides_obj%override_#@name, overrides_obj%#@name)" if @count 
    return str
  end

  attr_reader :count

  def initialize(p)
    @type = p[0]
    @name = p[1]
    @count = p[2]
  end
end 



parameter_list_geo = [
['real', 'rhoc'],
['real', 'qinp'],
['real', 'shat'],
['real', 'rgeo_lcfs'],
['real', 'rgeo_local'],
['real', 'akappa'],
['real', 'akappri'],
['real', 'tri'],
['real', 'tripri'],
['real', 'shift'],
['real', 'betaprim'],
].compact.map{|p| Generator.new(p)}

parameter_list_profs = [
['real', 'dens', 'nspec'],
['real', 'temp', 'nspec'],
['real', 'tprim', 'nspec'],
['real', 'fprim', 'nspec'],
['real', 'vnewk', 'nspec'],
['real', 'g_exb'],
['real', 'mach'],
].compact.map{|p| Generator.new(p)}

parameter_list_optimisations = [
['integer', 'nproc'],
['logical', 'opt_redist_nbk'],
['logical', 'opt_redist_persist'],
['logical', 'opt_redist_persist_overlap'],
['logical', 'intmom_sub'],
['logical', 'intspec_sub'],
['logical', 'local_field_solve'],
['character(len=5)', 'layout'],
['character(len=8)', 'field_option'],
['logical', 'field_subgath'],
['logical', 'do_smart_update'],
['logical', 'field_local_allreduce'],
['logical', 'field_local_allreduce_sub'],
['logical', 'opt_source'],
['integer', 'minnrow'],
].compact.map{|p| Generator.new(p)}

parameter_list_timestep = [
['logical', 'immediate_reset'],
].compact.map{|p| Generator.new(p)}

parameter_list_kt_grids = [
['integer', 'ny'],
['integer', 'naky'],
['integer', 'nx'],
['integer', 'ntheta0'],
['real', 'y0'],
['real', 'x0'],
['integer', 'jtwist'],
['logical', 'gryfx'],
].compact.map{|p| Generator.new(p)}



string = <<EOF
! DO NOT EDIT THIS FILE
! This file is automatically generated by overrides.rb

!> A module which defines the override types. These types
!! are used within the init object (which itself is contained
!! within the gs2_program_state object) to override values 
!! of the specified parameters (i.e. modify their values from
!! what is specified in the input file). The appropriate "prepare_..."
!! function from gs2_main must always be called before setting overrides.
module overrides
!> An object for overriding all or selected 
!! Miller geometry parameters.
#{Generator.generate_type('miller_geometry', parameter_list_geo)}
!> An object for overriding all or selected
!! profile parameters, for example species
!! temps, densities or gradients or the flow gradient or mach
!! number. Note that all species parameters are arrays of 
!! size nspec and you must set the override switches 
!! individually for each species.
#{Generator.generate_type('profiles', parameter_list_profs)}

!> A type for containing overrides to the processor layout
!! and optimisation flags for gs2. 
#{Generator.generate_type('optimisations', parameter_list_optimisations)}

!> A type for containing overrides to the perpendicular grids (x and y). 
#{Generator.generate_type('kt_grids', parameter_list_kt_grids)}

!> A type for containing overrides to the timestep and the cfl parameters
#{Generator.generate_type('timestep', parameter_list_timestep)}

!> A type for storing overrides of the intial
!! values of the fields and distribution function.
!! This override is different to all the others, 
!! because in order to minimise memory usage and disk writes,
!! this override is used internally during the simulation, and
!! its values can thus change over the course of the simulation.
!! In contrast, no other overrides are modified by running gs2.
!! Also, depending on the value of in_memory, the override
!! values will either be taken from the the arrays within
!! the object, or from the restart files. If you want
!! to externally modify the initial field and dist fn values,
!! you need to use in_memory = .true. If you just want to 
!! use this override to allow you to reinitialise the equations
!! and start from the same values, you can use either memory
!! or restart files. If you want to want to change the number
!! of processors and then reinitialise and then use this override
!! you must use in_memory = .false., because currently the memory
!! is allocated on a processor by processor basis. Changing
!! grid sizes and then using this override is not supported. 
!! This one is too complicated to generate 
!! automatically
type initial_values_overrides_type
  !> True if the object has been initialized.
  logical :: init = .false.
  !> If true, override values are read from the
  !! arrays in this object. If not, they are read
  !! from the restart files. The value of in_memory
  !! should not be changed without reinitializing this  
  !! object (doing so is an excellent way of generating
  !! segmentation faults).
  logical :: in_memory = .true.
  !> Whether to override initial values or not,
  !! i.e., whether or not this override is switched on.
  !! If it is switched on, initial values will be determined
  !! by the values in the arrays or the restart files,
  !! depending on the value of in_memory. If false, 
  !! initial values will be determined by the gs2 input file
  !! (note that of course, this can result in initial values
  !! being taken from the input files).
  logical :: override = .false.
  logical :: force_maxwell_reinit = .true.
  complex, dimension (:,:,:), pointer :: phi
  complex, dimension (:,:,:), pointer :: apar
  complex, dimension (:,:,:), pointer :: bpar
  complex, dimension (:,:,:), pointer :: g
end type initial_values_overrides_type

contains
#{Generator.generate_initialize('miller_geometry', parameter_list_geo)}
#{Generator.generate_finish('miller_geometry', parameter_list_geo)}
#{Generator.generate_initialize('profiles', parameter_list_profs)}
#{Generator.generate_finish('profiles', parameter_list_profs)}
#{Generator.generate_initialize('optimisations', parameter_list_optimisations)}
#{Generator.generate_finish('optimisations', parameter_list_optimisations)}
#{Generator.generate_initialize('kt_grids', parameter_list_kt_grids)}
#{Generator.generate_finish('kt_grids', parameter_list_kt_grids)}
#{Generator.generate_initialize('timestep', parameter_list_timestep)}
#{Generator.generate_finish('timestep', parameter_list_timestep)}

!> Warning: You can't change the value of overrides%force_maxwell_reinit 
!! or overrides%in_memory after calling this function
subroutine init_initial_values_overrides(overrides_obj, ntgrid, ntheta0, naky, g_llim, g_ulim, force_maxwell_reinit, in_memory)
  use file_utils, only: error_unit
  implicit none
  type(initial_values_overrides_type), intent(inout) :: overrides_obj
  integer, intent(in) :: ntgrid, ntheta0, naky, g_llim, g_ulim
  logical, intent(in) :: force_maxwell_reinit, in_memory
  integer :: iostat
  if (overrides_obj%init) return
  overrides_obj%init = .true.
  overrides_obj%override = .false.
  !overrides_obj%override_phi = .false.
  !overrides_obj%override_apar = .false.
  !overrides_obj%override_bpar = .false.
  !overrides_obj%override_g = .false.
  overrides_obj%force_maxwell_reinit = force_maxwell_reinit
  overrides_obj%in_memory = in_memory

  write (error_unit(), *) "INFO: changing force_maxwell_reinit or in_memory &
    & after calling initial_values_overrides_type will almost certainly cause &
    & segmentation faults."
  if (overrides_obj%in_memory) then 
    allocate(overrides_obj%g(-ntgrid:ntgrid,2,g_llim:g_ulim), stat=iostat)
    if (overrides_obj%force_maxwell_reinit) then 
      if (iostat.eq.0) allocate(overrides_obj%phi(-ntgrid:ntgrid,ntheta0,naky), stat=iostat)
      if (iostat.eq.0) allocate(overrides_obj%apar(-ntgrid:ntgrid,ntheta0,naky), stat=iostat)
      if (iostat.eq.0) allocate(overrides_obj%bpar(-ntgrid:ntgrid,ntheta0,naky), stat=iostat)
    end if
    if (iostat.ne.0) then
      overrides_obj%in_memory = .false.
      write(error_unit(),*) "WARNING: could not allocate memory for initial_values_overrides. Only restart from file possible (manual setting of initial values not possible)"
      if (associated(overrides_obj%g)) deallocate(overrides_obj%g)
      if (associated(overrides_obj%phi)) deallocate(overrides_obj%phi)
      if (associated(overrides_obj%apar)) deallocate(overrides_obj%apar)
      if (associated(overrides_obj%bpar)) deallocate(overrides_obj%bpar)
    end if
  end if
end subroutine init_initial_values_overrides

subroutine finish_initial_values_overrides(overrides_obj)
  implicit none
  type(initial_values_overrides_type), intent(inout) :: overrides_obj
  if (.not. overrides_obj%init) then
    write (*,*) "WARNING: Called finish_initial_values_overrides on an uninitialized object"
    return 
  end if
  overrides_obj%init = .false.
  overrides_obj%override = .false.
  !overrides%override_phi = .false.
  !overrides%override_apar = .false.
  !overrides%override_bpar = .false.
  !overrides%override_g = .false.
  overrides_obj%force_maxwell_reinit = .true.
  if (overrides_obj%in_memory) then 
    deallocate(overrides_obj%g)
    if (overrides_obj%force_maxwell_reinit) then 
      deallocate(overrides_obj%phi)
      deallocate(overrides_obj%apar)
      deallocate(overrides_obj%bpar)
    end if
  end if
end subroutine finish_initial_values_overrides

end module overrides
EOF

File.open(ARGV[-1], 'w'){|f| f.puts string}


