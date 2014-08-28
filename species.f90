module species
  implicit none

  public :: init_species, finish_species, reinit_species, init_trin_species, finish_trin_species
  public :: write_trinity_parameters
  public :: wnml_species, check_species
  public :: nspec, specie, spec
  public :: ion_species, electron_species, nonmaxw_species, tracer_species, sdequivmaxw_species
  public :: f0_maxwellian, f0_external, f0_sdanalytic, f0_sdsemianalytic, f0_kappa
  public :: has_electron_species, has_nonmaxw_species
  public :: calculate_slowingdown_parameters
  public :: ions, electrons, impurity

  type :: specie
     real :: z
     real :: mass
     real :: dens, dens0, u0
     real :: tpar0,tperp0
     real :: temp
     real :: tprim
     real :: fprim
     real :: uprim, uprim2
     real :: vnewk, nustar
     real :: nu, nu_h  ! nu will be the preferred collisionality parameter moving forward
                       ! as it will have a consistent v_t scaling
                       ! nu_h controls a hyperviscous term embedded in the collision operator
     real :: stm, zstm, tz, smz, zt
     real :: bess_fac !Artificial factor multiplying the Bessel function argument
     integer :: type
     integer :: f0_type
     logical :: passive_spec !< Zeros out any contribution to the fields from this species
  end type specie

  private

  integer, parameter :: ion_species = 1
  integer, parameter :: electron_species = 2 ! for collision operator
  integer, parameter :: nonmaxw_species = 3 ! Non-Maxwellian
  integer, parameter :: sdequivmaxw_species = 4 ! Maxwellian w/ same temperature analytic slowing-down distribution
  integer, parameter :: tracer_species = 5 ! for test particle diffusion studies

  integer, parameter :: f0_maxwellian = 1, &           !< Regular Maxwellian species
                        f0_external = 2, &             !< f0 determined from table in external input file
                        f0_sdanalytic = 3, &           !< Analytic Gaffey slowing-down distribution
                        f0_sdsemianalytic = 4, &       !< Abel's semi-analytic form of the slowing-down distribution, including ash (not currently implemented)
                        f0_kappa = 5                   !< Kappa distribution

  !> Various quantities needed in the calculation of the slowing-down distribution
  !! These belong here because the equivalent-Maxwellian properties are calculated here
  real:: me, ZI_fac, ni_prim, ne_prim, ne, vte

  !> Option for how to calculate vcrit for the equivalent Maxwellian
  !! Analagous to vcrit_opt in general_f0
  integer:: equivmaxw_opt = 1
 
  integer :: nspec
  type (specie), dimension (:), allocatable :: spec

  integer :: ions, electrons, impurity
  integer :: ntspec_trin
  real, dimension (:), allocatable :: dens_trin, temp_trin, fprim_trin, tprim_trin, nu_trin

  logical :: initialized = .false.
  logical :: exist

contains

  subroutine check_species(report_unit,beta,tite,alne,dbetadrho_spec)
  implicit none
  integer :: report_unit
  real :: beta, tite, alne, dbetadrho_spec
  integer :: is
  real :: aln, alp, charge, ee, ne, ptot, zeff_calc
     write (report_unit, fmt="('Number of species: ',i3)") nspec
     zeff_calc = 0.
     charge = 0.
     aln = 0.
     alne = 0.
     alp = 0.
     ptot = 0.
     do is=1, nspec
        write (report_unit, *) 
        write (report_unit, fmt="('  Species ',i3)") is
        if (spec(is)%type == 1) write (report_unit, fmt="('    Type:             Ion')")
        if (spec(is)%type == 2) write (report_unit, fmt="('    Type:             Electron')")
        if (spec(is)%type == 3) write (report_unit, fmt="('    Type:             Slowing-down')")
        write (report_unit, fmt="('    Charge:         ',f7.3)") spec(is)%z
        write (report_unit, fmt="('    Mass:             ',es10.4)") spec(is)%mass
        write (report_unit, fmt="('    Density:        ',f7.3)") spec(is)%dens
        write (report_unit, fmt="('    Temperature:    ',f7.3)") spec(is)%temp
        write (report_unit, fmt="('    Collisionality:   ',es10.4)") spec(is)%vnewk
        write (report_unit, fmt="('    Normalized Inverse Gradient Scale Lengths:')")
        write (report_unit, fmt="('      Temperature:  ',f7.3)") spec(is)%tprim
        write (report_unit, fmt="('      Density:      ',f7.3)") spec(is)%fprim
        write (report_unit, fmt="('      Parallel v:   ',f7.3)") spec(is)%uprim
        if (spec(is)%bess_fac.ne.1.0) &
             write (report_unit, fmt="('      Bessel function arg multiplied by:   ',f7.3)") spec(is)%bess_fac
!        write (report_unit, fmt="('    Ignore this:')")
!        write (report_unit, fmt="('    D_0: ',es10.4)") spec(is)%dens0
        if (spec(is)%type /= 2) then
           zeff_calc = zeff_calc + spec(is)%dens*spec(is)%z**2
           charge = charge + spec(is)%dens*spec(is)%z
           aln = aln + spec(is)%dens*spec(is)%z*spec(is)%fprim
        else
           alne = alne + spec(is)%dens*spec(is)%z*spec(is)%fprim
           ne = spec(is)%dens
           ee = spec(is)%z
        end if
        alp = alp + spec(is)%dens * spec(is)%temp *(spec(is)%fprim + spec(is)%tprim)
        ptot = ptot + spec(is)%dens * spec(is)%temp
     end do

     if (.not. has_electron_species(spec)) then
        ptot = ptot + 1./tite   ! electron contribution to pressure
        alp = alp + aln/tite    ! assuming charge neutrality, electron contribution to alp
     end if

     alp = alp / ptot

     write (report_unit, *) 
     write (report_unit, fmt="('------------------------------------------------------------')")

     write (report_unit, fmt="('Calculated Z_eff: ',f7.3)") zeff_calc

     if (has_electron_species(spec)) then
        if (abs(charge+ne*ee) > 1.e-2) then
           if (charge+ne*ee < 0.) then
              write (report_unit, *) 
              write (report_unit, fmt="('################# WARNING #######################')")
              write (report_unit, fmt="('You are neglecting an ion species.')")
              write (report_unit, fmt="('This species has a charge fraction of ',f7.3)") abs(charge+ne*ee)
              write (report_unit, &
                   & fmt="('and a normalized inverse density gradient scale length of ',f7.3)") &
                   (aln+alne)/(charge+ne*ee)
              write (report_unit, fmt="('################# WARNING #######################')")
           else
              write (report_unit, *) 
              write (report_unit, fmt="('################# WARNING #######################')")
              write (report_unit, fmt="('There is an excess ion charge fraction of ',f7.3)") abs(charge+ne*ee)
              write (report_unit, fmt="('THIS IS PROBABLY AN ERROR.')") 
              write (report_unit, fmt="('################# WARNING #######################')")
           end if
        else
           if (abs(aln+alne) > 1.e-2) then
              write (report_unit, *) 
              write (report_unit, fmt="('################# WARNING #######################')")
              write (report_unit, fmt="('The density gradients are inconsistent'/' a/lni =',e12.4,' but alne =',e12.4)") aln, alne
              write (report_unit, fmt="('################# WARNING #######################')")
           end if
        end if
     else
        if (charge > 1.01) then
           write (report_unit, *) 
           write (report_unit, fmt="('################# WARNING #######################')")
           write (report_unit, fmt="('There is an excess ion charge fraction of ',f7.3)") charge-1.
           write (report_unit, fmt="('THIS IS PROBABLY AN ERROR.')") 
           write (report_unit, fmt="('################# WARNING #######################')")
        end if
        if (charge < 0.99) then
           write (report_unit, *) 
           write (report_unit, fmt="('################# WARNING #######################')")
           write (report_unit, fmt="('You are neglecting an ion species.')")
           write (report_unit, fmt="('This species has a charge fraction of ',f7.3)") abs(charge-1.)
           write (report_unit, fmt="('################# WARNING #######################')")
        end if
     end if

     write (report_unit, *) 
     write (report_unit, fmt="('------------------------------------------------------------')")

     write (report_unit, *) 
     write (report_unit, fmt="('GS2 beta parameter = ',f9.4)") beta
     write (report_unit, fmt="('Total beta = ',f9.4)") beta*ptot
     write (report_unit, *) 
     write (report_unit, fmt="('The total normalized inverse pressure gradient scale length is ',f10.4)") alp
     dbetadrho_spec = -beta*ptot*alp
     write (report_unit, fmt="('corresponding to d beta / d rho = ',f10.4)") dbetadrho_spec

  end subroutine check_species

  subroutine wnml_species(unit)
  implicit none
  integer :: unit, i
  character (100) :: line
     if (.not. exist) return
       write (unit, *)
       write (unit, fmt="(' &',a)") "species_knobs"
       write (unit, fmt="(' nspec = ',i2)") nspec
       write (unit, fmt="(' /')")

       do i=1,nspec
          write (unit, *)
          write (line, *) i
          write (unit, fmt="(' &',a)") &
               & trim("species_parameters_"//trim(adjustl(line)))
          write (unit, fmt="(' z = ',e13.6)") spec(i)%z
          write (unit, fmt="(' mass = ',e13.6)") spec(i)%mass
          write (unit, fmt="(' dens = ',e13.6)") spec(i)%dens
          write (unit, fmt="(' temp = ',e13.6)") spec(i)%temp
          write (unit, fmt="(' tprim = ',e13.6)") spec(i)%tprim
          write (unit, fmt="(' fprim = ',e13.6)") spec(i)%fprim
          write (unit, fmt="(' uprim = ',e13.6)") spec(i)%uprim
          if (spec(i)%uprim2 /= 0.) write (unit, fmt="(' uprim2 = ',e13.6)") spec(i)%uprim2
          write (unit, fmt="(' vnewk = ',e13.6)") spec(i)%vnewk
          if (spec(i)%type == ion_species) &
               write (unit, fmt="(a)") ' type = "ion" /'
          if (spec(i)%type == electron_species) &
               write (unit, fmt="(a)") ' type = "electron"  /'
          if (spec(i)%type == nonmaxw_species) &
               write (unit, fmt="(a)") ' type = "fast"  /'
          write (unit, fmt="(' dens0 = ',e13.6)") spec(i)%dens0
          if(spec(i)%bess_fac.ne.1.0) &
               write (unit, fmt="(' bess_fac = ',e13.6)") spec(i)%bess_fac
       end do
  end subroutine wnml_species

  subroutine init_species
    use mp, only: trin_flag
    implicit none
!    logical, save :: initialized = .false.

    if (initialized) return
    initialized = .true.

    call read_parameters
    if (trin_flag) then
       call reinit_species (ntspec_trin, dens_trin, &
         temp_trin, fprim_trin, tprim_trin, nu_trin)
    endif
  end subroutine init_species

  subroutine read_parameters
    use file_utils, only: input_unit, error_unit, get_indexed_namelist_unit, input_unit_exist
    use text_options, only: text_option, get_option_value
    use mp, only: proc0, broadcast
    implicit none
    real :: z, mass, dens, dens0, u0, temp, tprim, fprim, uprim, uprim2, vnewk, nustar, nu, nu_h
    real :: tperp0, tpar0, bess_fac, vcrit, vcritprim
    character(20) :: type, f0_type
    integer :: unit
    integer :: is, iostat
    logical:: passive_spec
    namelist /species_knobs/ nspec, ZI_fac, me, equivmaxw_opt
    namelist /species_parameters/ z, mass, dens, dens0, u0, temp, &
         tprim, fprim, uprim, uprim2, vnewk, nustar, type, nu, nu_h, &
         tperp0, tpar0, bess_fac, f0_type, passive_spec
    integer :: ierr, in_file

    type (text_option), dimension (6), parameter :: typeopts = &
         (/ text_option('default', ion_species), &
            text_option('ion', ion_species), &
            text_option('electron', electron_species), &
            text_option('e', electron_species), &
            text_option('nonmaxw', nonmaxw_species), &
            text_option('trace', tracer_species) /)

    type (text_option), dimension (6), parameter :: f0_opts = &
         (/ text_option('maxwellian', f0_maxwellian), &
            text_option('external', f0_external), &
            text_option('sdanalytic', f0_sdanalytic), &
            text_option('sdsemianalytic', f0_sdsemianalytic), &
            text_option('external', f0_external) ,&
            text_option('kappa', f0_kappa) /)

    if (proc0) then
       nspec = 2
       ZI_fac = -1.0
       me = -1.0
       equivmaxw_opt = 1
       in_file = input_unit_exist("species_knobs", exist)
!       if (exist) read (unit=input_unit("species_knobs"), nml=species_knobs)
       if (exist) then
          read (unit=in_file, nml=species_knobs)
       else 
          write(6,*) 'Error: species_knobs namelist file does not exist'
       endif
       if (nspec < 1) then
          ierr = error_unit()
          write (unit=ierr, &
               fmt="('Invalid nspec in species_knobs: ', i5)") nspec
          stop
       end if
    end if

    call broadcast (nspec)
    call broadcast (ZI_fac)
    call broadcast (me)
    call broadcast (equivmaxw_opt)
    allocate (spec(nspec))

    if (proc0) then
       do is = 1, nspec
          call get_indexed_namelist_unit (unit, "species_parameters", is)
          z = 1
          mass = 1.0
          dens = 1.0
          dens0 = 1.0
          u0 = 1.0
          tperp0 = 0.
          tpar0 = 0.
          temp = 1.0
          tprim = 6.9
          fprim = 2.2
          uprim = 0.0
          uprim2 = 0.0
          nustar = -1.0
          vnewk = 0.0
          nu = -1.0
          nu_h = 0.0
          bess_fac=1.0
          type = "default"
          f0_type = "maxwellian"
          passive_spec = .false.
          read (unit=unit, nml=species_parameters, iostat=iostat)
          if(iostat /= 0) write(6,*) 'Error ',iostat,'reading species parameters'
          close (unit=unit, iostat=iostat)
          if(iostat /= 0) write(6,*) 'Error ',iostat,'closing species parameters namelist'
          spec(is)%z = z
          spec(is)%mass = mass
          spec(is)%dens = dens
          spec(is)%dens0 = dens0
          spec(is)%u0 = u0
          spec(is)%tperp0 = tperp0
          spec(is)%tpar0 = tpar0
          spec(is)%temp = temp
          spec(is)%tprim = tprim
          spec(is)%fprim = fprim
          spec(is)%uprim = uprim
          spec(is)%uprim2 = uprim2
          spec(is)%vnewk = vnewk
          spec(is)%nustar = nustar
          spec(is)%nu = nu
          spec(is)%nu_h = nu_h
          spec(is)%passive_spec = passive_spec

          spec(is)%stm = sqrt(temp/mass)
          spec(is)%zstm = z/sqrt(temp*mass)
          spec(is)%tz = temp/z
          spec(is)%zt = z/temp
          spec(is)%smz = abs(sqrt(temp*mass)/z)

          spec(is)%bess_fac=bess_fac

          ierr = error_unit()
          call get_option_value (type, typeopts, spec(is)%type, ierr, "type in species_parameters_x")
          call get_option_value (f0_type, f0_opts, spec(is)%f0_type, ierr, "f0_type in species_parameters_x")
       end do

       !> GW: When using the "equivalent Maxwellian" option, some funny things happen. This Maxwellian is calculated
       !! with the input spec(is)%temp = injection energy. Since it is Maxwellian though, it makes sense to redefine
       !! this to be the tempeature of the Maxwellian. This is the only sane place to do so because temperature is 
       !! required for so many other things from here on.

       ! If a species is a slowing-down type species, calculate appropriate quantities
       do is = 1, nspec
          ! If sdequivmaxw is the species type, change the definition of spec(is)%temp
          if ( spec(is)%type == sdequivmaxw_species) &
             call calculate_slowingdown_parameters(is,equivmaxw_opt,vcrit,vcritprim)
             call redefine_equivmaxw_temperature(is,vcrit,vcritprim)
       end do
    end if

    do is = 1, nspec
       call broadcast (spec(is)%z)
       call broadcast (spec(is)%mass)
       call broadcast (spec(is)%dens)
       call broadcast (spec(is)%dens0)
       call broadcast (spec(is)%u0)
       call broadcast (spec(is)%tperp0)
       call broadcast (spec(is)%tpar0)
       call broadcast (spec(is)%temp)
       call broadcast (spec(is)%tprim)
       call broadcast (spec(is)%fprim)
       call broadcast (spec(is)%uprim)
       call broadcast (spec(is)%uprim2)
       call broadcast (spec(is)%vnewk)
       call broadcast (spec(is)%nu)
       call broadcast (spec(is)%nu_h)
       call broadcast (spec(is)%nustar)
       call broadcast (spec(is)%stm)
       call broadcast (spec(is)%zstm)
       call broadcast (spec(is)%tz)
       call broadcast (spec(is)%zt)
       call broadcast (spec(is)%smz)
       call broadcast (spec(is)%type)
       call broadcast (spec(is)%f0_type)
       call broadcast (spec(is)%passive_spec)
       call broadcast (spec(is)%bess_fac)
    end do
  end subroutine read_parameters

  subroutine calculate_slowingdown_parameters(alpha_index,opt,vc,vcprim)
    use constants, only: pi
    implicit none
    integer, intent(in):: alpha_index, opt
    real, intent(inout):: vc, vcprim
    integer:: electron_spec, main_ion_species, is,js
    real:: vinj, Te_prim
    
    electron_spec = -1
    main_ion_species = -1

    do is = 1,nspec
       if (spec(is)%type .eq. electron_species) electron_spec = is
         if (main_ion_species < 1 .and. spec(is)%type .eq. ion_species) &
            main_ion_species = is
    end do


    if (electron_spec .GT. 0) then
       me = spec(electron_spec)%mass
       ne = spec(electron_spec)%dens
       ne_prim = spec(electron_spec)%fprim
       Te_prim = spec(electron_spec)%tprim
       vte = sqrt(spec(electron_spec)%temp/spec(electron_spec)%mass)
    else
       if (me .LT. 0.0) then
          write(*,*) "WARNING: vte not specified in species_knobs. Assuming reference species is deuterium, so me = 0.0002723085"
          me = 0.0002723085
       end if             

       ne = sum(spec(:)%z*spec(:)%dens)
       ne_prim = sum(spec(:)%z*spec(:)%dens*spec(:)%fprim)/ne
       Te_prim = spec(main_ion_species)%tprim
       vte = sqrt(spec(main_ion_species)%temp/spec(main_ion_species)%mass)
       write(*,*) "Since electrons are adiabatic, we need to improvise electron parameters to "
       write(*,*) "caluclate alpha species properties. Imposed by global quasineutrality:"
       write(*,*) "  ne = ", ne
       write(*,*) "  vte = ", vte
       write(*,*) "  ne_prim = ", ne_prim
       write(*,*) "  Te_prim = ", Te_prim
    end if

    ni_prim = 0.0
    ! If ZI_fac is not specified, calculate it from existing ion species:
    if (ZI_fac .LT. 0.0) then
       ZI_fac = 0.0
       do js = 1,nspec
          if (spec(js)%type .eq. ion_species) then 
             ZI_fac = ZI_fac   + spec(alpha_index)%mass*spec(js)%dens*spec(js)%z**2/(spec(js)%mass*ne)
             ni_prim = ni_prim + spec(alpha_index)%mass*spec(js)%dens*spec(js)%z**2*spec(js)%fprim/(spec(js)%mass*ne)
          end if
       end do
    end if
    ni_prim = ni_prim / ZI_fac 

    if (opt == 2) Te_prim = spec(alpha_index)%tprim
    
    ! Calculate vc/vinj
    vinj = sqrt(spec(alpha_index)%temp/spec(alpha_index)%mass)
    vc = (0.25*3.0*sqrt(pi)*ZI_fac*me/spec(alpha_index)%mass)**(1.0/3.0)*vte/vinj
    vcprim = ni_prim - ne_prim + 1.5*Te_prim

  end subroutine calculate_slowingdown_parameters
            
  subroutine redefine_equivmaxw_temperature(alpha_index,vcva,vcprim)
    use constants, only: pi
    implicit none
    integer, intent(in):: alpha_index 
    real, intent(in):: vcva,vcprim
    real:: Einj, vinj, z, temp, dveff2dvc,veff2va2, mass, Te_prim

    Einj = spec(alpha_index)%temp                    !< temp for alpha species is interpreted as normalized injection energy

    if (equivmaxw_opt .EQ. 2) Te_prim = spec(alpha_index)%tprim

    ! Calculate vteff^2/valpha^2
    veff2va2 = 1.0 - pi*vcva**2/(3.0**1.5) + (2.0*vcva**2/sqrt(3.0))*atan((vcva-2.0)/(sqrt(3.0)*vcva)) - (vcva**2/3.0)*log((1.0-vcva+vcva**2)/(1+vcva)**2)
    veff2va2 = veff2va2/log(1.0+(1.0/vcva)**3)

    ! Calculate d/dvc (vteff^2)
    dveff2dvc = veff2va2 * 3.0 / ( (1.0+vcva**3)*log(1.0+(1.0/vcva)**3))
    temp = 6.0*vcva/((1.0+vcva)*(1.0-vcva+vcva**2)) - 2.0*pi/sqrt(3.0) + 4.0*sqrt(3.0)*atan((vcva-2.0)/(sqrt(3.0)*vcva)) - 2.0*log((1.0-vcva+vcva**2)/(vcva+1.0)**2)
    dveff2dvc = dveff2dvc + (vcva**2/(3.0*log(1.0+(1.0/vcva)**3)))*temp

    spec(alpha_index)%temp = Einj*veff2va2

    spec(alpha_index)%tprim = (1.0/3.0)*dveff2dvc*vcprim/veff2va2

    ! Reclaculate the things that depend on temperature
    z = spec(alpha_index)%z     
    temp = spec(alpha_index)%temp
    mass = spec(alpha_index)%mass
    spec(alpha_index)%stm = sqrt(temp/mass)
    spec(alpha_index)%zstm = z/sqrt(temp*mass)
    spec(alpha_index)%tz = temp/z
    spec(alpha_index)%zt = z/temp
    spec(alpha_index)%smz = abs(sqrt(temp*mass)/z)

    write(*,*) "Using equivalent-Maxwellian option for species ", alpha_index
    write(*,*) "Parameters have been changed to the following values:"
    write(*,*) "  vc/va = ", vcva
    write(*,*) "  temp = ", spec(alpha_index)%temp
    write(*,*) "  tprim = ", spec(alpha_index)%tprim

  end subroutine redefine_equivmaxw_temperature

  pure function has_electron_species (spec)
    implicit none
    type (specie), dimension (:), intent (in) :: spec
    logical :: has_electron_species
    has_electron_species = any(spec%type == electron_species)
  end function has_electron_species

  pure function has_nonmaxw_species (spec)
    implicit none
    type (specie), dimension (:), intent (in) :: spec
    logical :: has_nonmaxw_species
    has_nonmaxw_species = any(spec%type == nonmaxw_species)
  end function has_nonmaxw_species

  subroutine finish_species

    implicit none

    if(allocated(spec)) deallocate (spec)

    initialized = .false.

  end subroutine finish_species

  subroutine finish_trin_species

    implicit none

    call finish_species

    if (allocated(dens_trin)) deallocate(dens_trin)
    if (allocated(temp_trin)) deallocate(temp_trin)
    if (allocated(fprim_trin)) deallocate(fprim_trin)
    if (allocated(tprim_trin)) deallocate(tprim_trin)
    if (allocated(nu_trin)) deallocate(nu_trin)

  end subroutine finish_trin_species



  subroutine reinit_species (ntspec, dens, temp, fprim, tprim, nu)

    use mp, only: broadcast, proc0
    use job_manage, only: trin_restart

    implicit none

    integer, intent (in) :: ntspec
    real, dimension (:), intent (in) :: dens, fprim, temp, tprim, nu

    integer :: is
    logical, save :: first = .true.

    if(trin_restart) first = .true.

    if (first) then
       if (nspec == 1) then
          ions = 1
          electrons = 0
          impurity = 0
       else
          ! if 2 or more species in GS2 calculation, figure out which is main ion
          ! and which is electron via mass (main ion mass assumed to be one)
          do is = 1, nspec
             if (abs(spec(is)%mass-1.0) <= epsilon(0.0)) then
                ions = is
             else if (spec(is)%mass < 0.3) then
                ! for electrons, assuming electrons are at least a factor of 3 less massive
                ! than main ion and other ions are no less than 30% the mass of the main ion
                electrons = is
             else if (spec(is)%mass > 1.0 + epsilon(0.0)) then
                impurity = is
             else
                if (proc0) write (*,*) &
                     "Error: TRINITY requires the main ions to have mass 1", &
                     "and the secondary ions to be impurities (mass > 1)"
                stop
             end if
          end do
       end if
       first = .false.
    end if

    if (proc0) then

       nspec = ntspec

       ! TRINITY passes in species in following order: main ion, electron, impurity (if present)

       ! for now, hardwire electron density to be reference density
       ! main ion temperature is reference temperature
       ! main ion mass is assumed to be the reference mass
       
       ! if only 1 species in the GS2 calculation, it is assumed to be main ion
       ! and ion density = electron density
       if (nspec == 1) then
          spec(1)%dens = 1.0
          spec(1)%temp = 1.0
          spec(1)%fprim = fprim(1)
          spec(1)%tprim = tprim(1)
          spec(1)%vnewk = nu(1)
       else
          spec(ions)%dens = dens(1)/dens(2)
          spec(ions)%temp = 1.0
          spec(ions)%fprim = fprim(1)
          spec(ions)%tprim = tprim(1)
          spec(ions)%vnewk = nu(1)

          spec(electrons)%dens = 1.0
          spec(electrons)%temp = temp(2)/temp(1)
          spec(electrons)%fprim = fprim(2)
          spec(electrons)%tprim = tprim(2)
          spec(electrons)%vnewk = nu(2)

          if (nspec > 2) then
             spec(impurity)%dens = dens(3)/dens(2)
             spec(impurity)%temp = temp(3)/temp(1)
             spec(impurity)%fprim = fprim(3)
             spec(impurity)%tprim = tprim(3)
             spec(impurity)%vnewk = nu(3)
          end if
       end if

       do is = 1, nspec
          spec(is)%stm = sqrt(spec(is)%temp/spec(is)%mass)
          spec(is)%zstm = spec(is)%z/sqrt(spec(is)%temp*spec(is)%mass)
          spec(is)%tz = spec(is)%temp/spec(is)%z
          spec(is)%zt = spec(is)%z/spec(is)%temp
          spec(is)%smz = abs(sqrt(spec(is)%temp*spec(is)%mass)/spec(is)%z)

!          write (*,100) 'reinit_species', rhoc_ms, spec(is)%temp, spec(is)%fprim, &
!               spec(is)%tprim, spec(is)%vnewk, real(is)
       end do

    end if

!100 format (a15,9(1x,1pg18.11))

    call broadcast (nspec)

    do is = 1, nspec
       call broadcast (spec(is)%dens)
       call broadcast (spec(is)%temp)
       call broadcast (spec(is)%fprim)
       call broadcast (spec(is)%tprim)
       call broadcast (spec(is)%vnewk)
       call broadcast (spec(is)%stm)
       call broadcast (spec(is)%zstm)
       call broadcast (spec(is)%tz)
       call broadcast (spec(is)%zt)
       call broadcast (spec(is)%smz)
    end do

  end subroutine reinit_species

  subroutine write_trinity_parameters(trinpars_unit)
    integer, intent(in) :: trinpars_unit
    integer :: is
    do is = 1,nspec
      if (is<10) then
        write(trinpars_unit, "(A20,I1)") '&species_parameters_', is
      else
        write(trinpars_unit, "(A20,I2)") '&species_parameters_', is
      end if
      write (trinpars_unit, *) ' temp = ', spec(is)%temp
      write (trinpars_unit, *) ' dens = ', spec(is)%dens
      write (trinpars_unit, *) ' tprim = ', spec(is)%tprim
      write (trinpars_unit, *) ' fprim = ', spec(is)%fprim
      write (trinpars_unit, *) ' vnewk = ', spec(is)%vnewk
      write (trinpars_unit, "(A1)") '/'
    end do

  end subroutine write_trinity_parameters

  subroutine init_trin_species (ntspec_in, dens_in, temp_in, fprim_in, tprim_in, nu_in)

    implicit none

    integer, intent (in) :: ntspec_in
    real, dimension (:), intent (in) :: dens_in, fprim_in, temp_in, tprim_in, nu_in


    if (.not. allocated(dens_trin)) allocate (dens_trin(size(dens_in)))
    if (.not. allocated(fprim_trin)) allocate (fprim_trin(size(fprim_in)))
    if (.not. allocated(temp_trin)) allocate (temp_trin(size(temp_in)))
    if (.not. allocated(tprim_trin)) allocate (tprim_trin(size(tprim_in)))
    if (.not. allocated(nu_trin)) allocate (nu_trin(size(nu_in)))

    ntspec_trin = ntspec_in
    dens_trin = dens_in
    temp_trin = temp_in
    fprim_trin = fprim_in
    tprim_trin = tprim_in
    nu_trin = nu_in

  end subroutine init_trin_species

end module species
