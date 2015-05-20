# This Ruby script automatically generates the module optimisation_config. It is compatible with any version of Ruby, which means that it should work out of the box on any system, since even the most decrepit systems usually have Ruby 1.8.7. It is automatically invoked by the Makefile; thus, after editing it a simple make will trigger the generation of the file optimisation_config.f90.
#

# This is a list of all the input parameters to the namelist
# optimisation_config, with their default values.
# Leave third element of array empty to use the default default
#
# This list is used in generating optimisation_config.f90
input_variables_for_optimisation_config = [
  ['logical', 'on', '.false.'],
  ['logical', 'auto', '.true.'],
  ['logical', 'measure_all', '.false.'],
  ['logical', 'warm_up', '.false.'],
  ['integer', 'nstep_measure', '5'],
  ['real', 'max_imbalance', '-1'],
  ['integer', 'max_unused_procs', '0'],
  ['real', 'min_efficiency', '-1.0'],

]


class Generator
  attr_accessor :name, :type
  def initialize(type, name, default)
    @type = type
    @name = name
    @default = default
  end
  def declaration
    "#@type :: #@name"
  end
  def set_default
    "#@name = #{default}"
  end
  def default
    @default || case type
                when /logical/
                  '.false.'
                when /integer/
                  '1'
                end
  end
  def parameters_type_value
    "optim%#@name"
  end
  def set_parameters_type_value
    "#{parameters_type_value} = #@name"
  end
  def broadcast
    "call broadcast (#{parameters_type_value})"
  end
end

begin
  4.times.map{|i|}
rescue
  puts "You appear to be running ruby 1.8.6 or lower... suggest you upgrade your ruby version!"
  class Integer
    def times(&block)
      if block
        (0...self).to_a.each{|i| yield(i)}
      else
        return  (0...self).to_a
      end
    end
  end
end
generators = input_variables_for_optimisation_config.map{|type, name, default| Generator.new(type,name,default)}

string = <<EOF

! DO NOT EDIT THIS FILE
! This file has been automatically generated using generate_optimisation_config.rb

!> A module for handling the configuration of the optimisation
!! module via the namelist optimisation_config.
module optimisation_config
  use overrides, only: optimisations_overrides_type
  implicit none

  private

  public :: init_optimisation_config
  public :: finish_optimisation_config
  public :: optimisation_type
  public :: optimisation_results_type

  type optimisation_results_type
    ! Configuration

    ! Results
    real :: time
    real :: optimal_time
    real :: cost
    real :: optimal_cost
    real :: efficiency
    integer :: nproc
    logical :: optimal = .true.

  end type optimisation_results_type


  !> A type for storing the optimisation configuration,
  !! the results
  type optimisation_type
    integer :: nproc_max
    type(optimisation_results_type) :: results
    type(optimisations_overrides_type), &
      dimension(:), pointer :: sorted_optimisations
    type(optimisation_results_type), dimension(:), pointer :: sorted_results
    integer :: outunit
     #{generators.map{|g| g.declaration}.join("\n     ") }
  end type optimisation_type

contains
  subroutine init_optimisation_config(optim)
    use file_utils, only: open_output_file
    use mp, only: nproc
    implicit none
    type(optimisation_type), intent(inout) :: optim
    call read_parameters(optim)
    call open_output_file(optim%outunit, '.optim')
    optim%nproc_max = nproc
  end subroutine init_optimisation_config

  subroutine finish_optimisation_config(optim)
    implicit none
    type(optimisation_type), intent(inout) :: optim
  end subroutine finish_optimisation_config


  subroutine read_parameters(optim)
    use file_utils, only: input_unit, error_unit, input_unit_exist
    use text_options, only: text_option, get_option_value
    use mp, only: proc0, broadcast
    implicit none
    type(optimisation_type), intent(inout) :: optim
    #{generators.map{|g| g.declaration}.join("\n    ") }
    namelist /optimisation_config/ &
         #{generators.map{|g| g.name}.join(", &\n         ")}

    integer :: in_file
    logical :: exist

    if (proc0) then
       #{generators.map{|g| g.set_default}.join("\n       ")}

       in_file = input_unit_exist ("optimisation_config", exist)
       if (exist) read (unit=in_file, nml=optimisation_config)

       #{generators.map{|g| g.set_parameters_type_value}.join("\n       ")}

    end if

    #{generators.map{|g| g.broadcast}.join("\n    ")}
    
  end subroutine read_parameters
end module optimisation_config

EOF

File.open(ARGV[-1], 'w'){|f| f.puts string}