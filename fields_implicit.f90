module fields_implicit
  use fields_arrays, only: nidx
  implicit none

  public :: init_fields_implicit
  public :: advance_implicit
  public :: remove_zonal_flows
  public :: init_allfields_implicit
  public :: nidx
  public :: reset_init
  public :: set_scan_parameter
  public :: field_subgath

  !> Unit tests
  public :: fields_implicit_unit_test_init_fields_implicit

  private

  integer, save :: nfield
  logical :: initialized = .false.
  logical :: linked = .false.
  logical :: field_subgath

contains

  subroutine init_fields_implicit
    use antenna, only: init_antenna
    use theta_grid, only: init_theta_grid
    use kt_grids, only: init_kt_grids
    use gs2_layouts, only: init_gs2_layouts
    use parameter_scan_arrays, only: run_scan
    implicit none
    logical:: debug=.false.
    logical :: dummy

    if (initialized) return
    initialized = .true.

    if (debug) write(6,*) "init_fields_implicit: gs2_layouts"
    call init_gs2_layouts
    if (debug) write(6,*) "init_fields_implicit: theta_grid"
    call init_theta_grid
    if (debug) write(6,*) "init_fields_implicit: kt_grids"
    call init_kt_grids
    if (debug) write(6,*) "init_fields_implicit: read_parameters"
    call read_parameters
    if (debug .and. run_scan) &
        write(6,*) "init_fields_implicit: set_scan_parameter"
        ! Must be done before resp. m.
        if (run_scan) call set_scan_parameter(dummy)
    if (debug) write(6,*) "init_fields_implicit: response_matrix"
    call init_response_matrix
    if (debug) write(6,*) "init_fields_implicit: antenna"
    call init_antenna

  end subroutine init_fields_implicit

  function fields_implicit_unit_test_init_fields_implicit()
    logical :: fields_implicit_unit_test_init_fields_implicit

    call init_fields_implicit

    fields_implicit_unit_test_init_fields_implicit = .true.

  end function fields_implicit_unit_test_init_fields_implicit

  
  subroutine set_scan_parameter(reset)
    !use parameter_scan_arrays, only: current_scan_parameter_value
    !use parameter_scan_arrays, only: scan_parameter_switch
    !use parameter_scan_arrays, only: scan_parameter_tprim
    !use parameter_scan_arrays, only: scan_parameter_g_exb
    use parameter_scan_arrays
    use species, only: spec 
    use dist_fn, only: g_exb
    use mp, only: proc0
    logical, intent (inout) :: reset
     
    select case (scan_parameter_switch)
    case (scan_parameter_tprim)
       spec(scan_spec)%tprim = current_scan_parameter_value
       if (proc0) write (*,*) &
         "Set scan parameter tprim_1 to ", spec(scan_spec)%tprim
       reset = .true.
    case (scan_parameter_g_exb)
       g_exb = current_scan_parameter_value
       if (proc0) write (*,*) &
         "Set scan parameter g_exb to ", g_exb
       reset = .false.
    end select
  end subroutine set_scan_parameter

  subroutine read_parameters
  end subroutine read_parameters

  subroutine init_allfields_implicit

    use fields_arrays, only: phi, apar, bpar, phinew, aparnew, bparnew
    use dist_fn_arrays, only: g, gnew
    use dist_fn, only: get_init_field
    use init_g, only: new_field_init

    implicit none

    ! MAB> new field init option ported from agk
    if (new_field_init) then
       call get_init_field (phinew, aparnew, bparnew)
       phi = phinew; apar = aparnew; bpar = bparnew; g = gnew
    else
       call getfield (phinew, aparnew, bparnew)
       phi = phinew; apar = aparnew; bpar = bparnew
    end if
    ! <MAB

  end subroutine init_allfields_implicit

  subroutine get_field_vector (fl, phi, apar, bpar)
    use theta_grid, only: ntgrid
    use kt_grids, only: naky, ntheta0
    use dist_fn, only: getfieldeq
    use run_parameters, only: fphi, fapar, fbpar
    use prof, only: prof_entering, prof_leaving
    implicit none
    complex, dimension (-ntgrid:,:,:), intent (in) :: phi, apar, bpar
    complex, dimension (:,:,:), intent (out) :: fl
    complex, dimension (:,:,:), allocatable :: fieldeq, fieldeqa, fieldeqp
    integer :: istart, ifin

    call prof_entering ("get_field_vector", "fields_implicit")

    allocate (fieldeq (-ntgrid:ntgrid,ntheta0,naky))
    allocate (fieldeqa(-ntgrid:ntgrid,ntheta0,naky))
    allocate (fieldeqp(-ntgrid:ntgrid,ntheta0,naky))

    call getfieldeq (phi, apar, bpar, fieldeq, fieldeqa, fieldeqp)

    ifin = 0

    if (fphi > epsilon(0.0)) then
       istart = ifin + 1
       ifin = (istart-1) + 2*ntgrid+1
       fl(istart:ifin,:,:) = fieldeq
    end if

    if (fapar > epsilon(0.0)) then
       istart = ifin + 1
       ifin = (istart-1) + 2*ntgrid+1
       fl(istart:ifin,:,:) = fieldeqa
    end if

    if (fbpar > epsilon(0.0)) then
       istart = ifin + 1
       ifin = (istart-1) + 2*ntgrid+1
       fl(istart:ifin,:,:) = fieldeqp
    end if

    deallocate (fieldeq, fieldeqa, fieldeqp)

    call prof_leaving ("get_field_vector", "fields_implicit")
  end subroutine get_field_vector

  subroutine get_field_solution (u)
    use fields_arrays, only: phinew, aparnew, bparnew
    use theta_grid, only: ntgrid
    use kt_grids, only: naky, ntheta0
    use run_parameters, only: fphi, fapar, fbpar
    use gs2_layouts, only: jf_lo, ij_idx
    use prof, only: prof_entering, prof_leaving
    implicit none
    complex, dimension (0:), intent (in) :: u
    integer :: ik, it, ifield, ll, lr

    call prof_entering ("get_field_solution", "fields_implicit")

    ifield = 0

    if (fphi > epsilon(0.0)) then
       ifield = ifield + 1
       do ik = 1, naky
          do it = 1, ntheta0
             ll = ij_idx (jf_lo, -ntgrid, ifield, ik, it)
             lr = ll + 2*ntgrid
             phinew(:,it,ik) = u(ll:lr)
          end do
       end do
    endif

    if (fapar > epsilon(0.0)) then
       ifield = ifield + 1
       do ik = 1, naky
          do it = 1, ntheta0
             ll = ij_idx (jf_lo, -ntgrid, ifield, ik, it)
             lr = ll + 2*ntgrid
             aparnew(:,it,ik) = u(ll:lr)
          end do
       end do
    endif

    if (fbpar > epsilon(0.0)) then
       ifield = ifield + 1
       do ik = 1, naky
          do it = 1, ntheta0
             ll = ij_idx (jf_lo, -ntgrid, ifield, ik, it)
             lr = ll + 2*ntgrid
             bparnew(:,it,ik) = u(ll:lr)
          end do
       end do
    endif

    call prof_leaving ("get_field_solution", "fields_implicit")
  end subroutine get_field_solution

  subroutine getfield (phi, apar, bpar)
    use kt_grids, only: naky, ntheta0
    use gs2_layouts, only: f_lo, jf_lo, ij, mj, dj
    use prof, only: prof_entering, prof_leaving
    use fields_arrays, only: aminv, time_field
    use theta_grid, only: ntgrid
    use dist_fn, only: N_class
    use mp, only: sum_allreduce, allgatherv, iproc,nproc, proc0
    use job_manage, only: time_message
    implicit none
    complex, dimension (-ntgrid:,:,:), intent (in) :: phi, apar, bpar
    complex, dimension (:,:,:), allocatable :: fl
    complex, dimension (:), allocatable :: u
    complex, dimension (:), allocatable :: u_small
    integer :: jflo, ik, it, nl, nr, i, m, n, dc
    integer, dimension(:), allocatable,save :: recvcnts, displs

    if (proc0) call time_message(.false.,time_field,' Field Solver')

    call prof_entering ("getfield", "fields_implicit")
    allocate (fl(nidx, ntheta0, naky))

    !On first call to this routine setup the receive counts (recvcnts)
    !and displacement arrays (displs)
    if ((.not.allocated(recvcnts)).and.field_subgath) then
       allocate(recvcnts(nproc),displs(nproc)) !Note there's no matching deallocate
       do i=0,nproc-1
          displs(i+1)=MIN(i*jf_lo%blocksize,jf_lo%ulim_world+1) !This will assign a displacement outside the array for procs with no data
          recvcnts(i+1)=MIN(jf_lo%blocksize,jf_lo%ulim_world-displs(i+1)+1) !This ensures that we expect no data from procs without any
       enddo
    endif

    ! am*u = fl, Poisson's and Ampere's law, u is phi, apar, bpar 
    ! u = aminv*fl

    call get_field_vector (fl, phi, apar, bpar)

    !Initialise array, if not gathering then have to zero entire array
    if(field_subgath) then
       allocate(u_small(jf_lo%llim_proc:jf_lo%ulim_proc))
    else
       allocate(u_small(0:nidx*ntheta0*naky-1))
    endif
    u_small=0.

    !Should this really be to ulim_alloc instead?
    do jflo = jf_lo%llim_proc, jf_lo%ulim_proc
       
       !Class index
       i = ij(jflo)
       
       !Class member index (i.e. which member of the class)
       m = mj(jflo)

       !Get ik index
       ik = f_lo(i)%ik(m,1)  ! For fixed i and m, ik does not change as n varies 

       !Get d(istributed) cell index
       dc = dj(i,jflo)
       
       !Loop over cells in class (these are the 2pi domains in flux tube/box mode)
       do n = 1, N_class(i)
          
          !Get it index
          it = f_lo(i)%it(m,n)
          
          !Get extent of current cell in extended/ballooning space domain
          nl = 1 + nidx*(n-1)
          nr = nl + nidx - 1
          
          !Perform section of matrix vector multiplication
          u_small(jflo)=u_small(jflo)-sum(aminv(i)%dcell(dc)%supercell(nl:nr)*fl(:, it, ik)) 
          
       end do
    end do

    !Free memory
    deallocate (fl)

    !Gather/reduce the remaining data
    if(field_subgath) then
       allocate (u (0:nidx*ntheta0*naky-1))
       call allgatherv(u_small,recvcnts(iproc+1),u,recvcnts,displs)
       deallocate(u_small)
    else
       call sum_allreduce(u_small)
    endif

    !Reshape data into field arrays and free memory
    if(field_subgath)then
       call get_field_solution (u)
       deallocate(u)
    else
       call get_field_solution (u_small)
       deallocate(u_small)
    endif

    !For profiling
    call prof_leaving ("getfield", "fields_implicit")

    !For timing
    if (proc0) call time_message(.false.,time_field,' Field Solver')

  end subroutine getfield

  subroutine advance_implicit (istep, remove_zonal_flows_switch)
    use fields_arrays, only: phi, apar, bpar, phinew, aparnew, bparnew
    use fields_arrays, only: apar_ext !, phi_ext
    use antenna, only: antenna_amplitudes, no_driver
    use dist_fn, only: timeadv, exb_shear
    use dist_fn_arrays, only: g, gnew, kx_shift, theta0_shift
    implicit none
    integer :: diagnostics = 1
    integer, intent (in) :: istep
    logical, intent (in) :: remove_zonal_flows_switch


    !GGH NOTE: apar_ext is initialized in this call
    if(.not.no_driver) call antenna_amplitudes (apar_ext)
       
    if (allocated(kx_shift) .or. allocated(theta0_shift)) call exb_shear (gnew, phinew, aparnew, bparnew) 
    
    g = gnew
    phi = phinew
    apar = aparnew 
    bpar = bparnew       
    
    call timeadv (phi, apar, bpar, phinew, aparnew, bparnew, istep)
    if(.not.no_driver) aparnew = aparnew + apar_ext 
    
    call getfield (phinew, aparnew, bparnew)
    
    phinew   = phinew  + phi
    aparnew  = aparnew + apar
    bparnew  = bparnew + bpar

    if (remove_zonal_flows_switch) call remove_zonal_flows
    
    call timeadv (phi, apar, bpar, phinew, aparnew, bparnew, istep, diagnostics)
    
  end subroutine advance_implicit

  subroutine remove_zonal_flows
    use fields_arrays, only: phinew
    use theta_grid, only: ntgrid
    use kt_grids, only: ntheta0, naky
    
    complex, dimension(:,:,:), allocatable :: phi_avg

    allocate(phi_avg(-ntgrid:ntgrid,ntheta0,naky)) 
    phi_avg = 0.
    ! fieldline_average_phi will calculate the field line average of phinew and 
    ! put it into phi_avg, but only for ik = 1 (the last parameter of the call)
    call fieldline_average_phi(phinew, phi_avg, 1)
    phinew = phinew - phi_avg
    deallocate(phi_avg)
  end subroutine remove_zonal_flows

  !> This generates a field line average of phi_in and writes it to 
  !! phi_average. If ik_only is supplied, it will only calculate the
  !! field line average for that ky, leaving the rest of phi_avg unchanged. EGH
  
  ! It replaces the routines fieldlineavgphi_loc and fieldlineavgphi_tot,
  ! in fields.f90, which I  think are defunct, as phi is always on every processor.

  subroutine fieldline_average_phi (phi_in, phi_average, ik_only)
    use theta_grid, only: ntgrid, drhodpsi, gradpar, bmag, delthet
    use kt_grids, only: ntheta0, naky

    implicit none
    complex, dimension (-ntgrid:,:,:), intent (in) :: phi_in
    complex, dimension (-ntgrid:,:,:), intent (out) :: phi_average
    integer, intent (in), optional :: ik_only
    real, dimension (-ntgrid:ntgrid) :: jac
    !complex, dimension (-ntgrid:ntgrid) :: phi_avg_line
    complex :: phi_avg_line
    integer it, ik, ik_only_actual
    ik_only_actual = -1
    if (present(ik_only)) ik_only_actual = ik_only

    jac = 1.0/abs(drhodpsi*gradpar*bmag)
    if (ik_only_actual .gt. 0) then
      do it = 1,ntheta0
         phi_avg_line = sum(phi_in(-ntgrid:ntgrid,it,ik_only_actual)* &
            jac(-ntgrid:ntgrid)*delthet(-ntgrid:ntgrid))/ &
            sum(delthet(-ntgrid:ntgrid)*jac(-ntgrid:ntgrid))
           phi_average(:, it, ik_only_actual) = phi_avg_line
      end do
    else
      do it = 1,ntheta0
        do ik = 1,naky
          phi_average(:, it, ik) = sum(phi_in(-ntgrid:ntgrid,it,ik)*jac*delthet)/sum(delthet*jac)
        end do
      end do
    end if

  end subroutine fieldline_average_phi


  subroutine reset_init

    use fields_arrays, only: aminv
    integer :: i, j
    initialized = .false.

    if (.not. allocated (aminv)) return
    do i = 1, size(aminv)
       if (.not. associated (aminv(i)%dcell)) cycle
       do j = 1, size(aminv(i)%dcell)
          if (associated (aminv(i)%dcell(j)%supercell)) &
               deallocate(aminv(i)%dcell(j)%supercell)
       end do
       if (associated (aminv(i)%dcell)) deallocate (aminv(i)%dcell)
    end do
    deallocate (aminv)

  end subroutine reset_init

  subroutine init_response_matrix
    use mp, only: barrier
!   use mp, only: proc0
    use fields_arrays, only: phi, apar, bpar, phinew, aparnew, bparnew
    use theta_grid, only: ntgrid
    use kt_grids, only: naky, ntheta0
    use dist_fn_arrays, only: g
    use dist_fn, only: M_class, N_class, i_class
    use run_parameters, only: fphi, fapar, fbpar
    use gs2_layouts, only: init_fields_layouts, f_lo
    use gs2_layouts, only: init_jfields_layouts
    use prof, only: prof_entering, prof_leaving
    implicit none
    integer :: ig, ifield, it, ik, i, m, n
    complex, dimension(:,:), allocatable :: am
    logical :: endpoint

    call prof_entering ("init_response_matrix", "fields_implicit")

    nfield = 0
    if (fphi > epsilon(0.0)) nfield = nfield + 1
    if (fapar > epsilon(0.0)) nfield = nfield + 1
    if (fbpar > epsilon(0.0)) nfield = nfield + 1
    nidx = (2*ntgrid+1)*nfield

    call init_fields_layouts (nfield, nidx, naky, ntheta0, M_class, N_class, i_class)
    call init_jfields_layouts (nfield, nidx, naky, ntheta0, i_class)
    call finish_fields_layouts
!
! keep storage cost down by doing one class at a time
! Note: could define a superclass (of all classes), a structure containing all am, 
! then do this all at once.  This would be faster, especially for large runs in a 
! sheared domain, and could be triggered by local_field_solve 
! 

!<DD> Comments
!A class refers to a class of connected domain.
!These classes are defined by the extent of the connected domain, there can be 
!many members of each class.
!There are i_class classes in total.
!N_class(ic) is a count of how many 2pi domains there are in members of class ic
!M_class(ic) is how many members of class ic there are.
!Sum N_class(ic)*M_class(ic) for ic=1,i_class is naky*ntheta0
!In comments cell refers to a 2pi domain whilst supercell is the connected domain,
!i.e. we have classes of supercells based on the number of cells they contain.

    do i = i_class, 1, -1
       !Pretty sure this barrier is not needed
       call barrier
!       if (proc0) write(*,*) 'beginning class ',i,' with size ',nidx*N_class(i)
       !Allocate matrix am. First dimension is basically theta along the entire
       !connected domain for each field. Second dimension is the local section
       !of the M_class(i)*N_Class(i)*(2*ntgrid+1)*nfield compound domain.
       !Clearly this will 
       allocate (am(nidx*N_class(i), f_lo(i)%llim_proc:f_lo(i)%ulim_alloc))


       !Do we need to zero all 8 arrays on every loop? This can be more expensive than might think.
       am = 0.0
       g = 0.0
       
       phi = 0.0
       apar = 0.0
       bpar = 0.0
       phinew = 0.0
       aparnew = 0.0
       bparnew = 0.0

       !Loop over individual 2pi domains / cells
       do n = 1, N_class(i)
          !Loop over theta grid points in cell
          !This is like a loop over nidx as we also handle all the fields in this loop
          do ig = -ntgrid, ntgrid
             !Are we at a connected boundary point on the lower side (i.e. left hand end of a
             !tube/cell connected to the left)
             endpoint = n > 1
             endpoint = ig == -ntgrid .and. endpoint

             !Start counting fields
             ifield = 0

             !Find response to phi
             if (fphi > epsilon(0.0)) then
                ifield = ifield + 1
                if (endpoint) then
                   !Do all members of supercell together
                   do m = 1, M_class(i)
                      ik = f_lo(i)%ik(m,n-1)
                      it = f_lo(i)%it(m,n-1)
                      phinew(ntgrid,it,ik) = 1.0
                   end do
                endif
                !Do all members of supercell together
                do m = 1, M_class(i)
                   ik = f_lo(i)%ik(m,n)
                   it = f_lo(i)%it(m,n)
                   phinew(ig,it,ik) = 1.0
                end do
                call init_response_row (ig, ifield, am, i, n)
                phinew = 0.0
             end if
             
             !Find response to apar
             if (fapar > epsilon(0.0)) then
                ifield = ifield + 1
                if (endpoint) then
                   !Do all members of supercell together
                   do m = 1, M_class(i)
                      ik = f_lo(i)%ik(m,n-1)
                      it = f_lo(i)%it(m,n-1)
                      aparnew(ntgrid,it,ik) = 1.0
                   end do
                endif
                !Do all members of supercell together
                do m = 1, M_class(i)
                   ik = f_lo(i)%ik(m,n)
                   it = f_lo(i)%it(m,n)
                   aparnew(ig,it,ik) = 1.0
                end do
                call init_response_row (ig, ifield, am, i, n)
                aparnew = 0.0
             end if
             
             !Find response to bpar
             if (fbpar > epsilon(0.0)) then
                ifield = ifield + 1
                if (endpoint) then
                   !Do all members of supercell together
                   do m = 1, M_class(i)
                      ik = f_lo(i)%ik(m,n-1)
                      it = f_lo(i)%it(m,n-1)
                      bparnew(ntgrid,it,ik) = 1.0
                   end do
                endif
                !Do all members of supercell together
                do m = 1, M_class(i)
                   ik = f_lo(i)%ik(m,n)
                   it = f_lo(i)%it(m,n)
                   bparnew(ig,it,ik) = 1.0
                end do
                call init_response_row (ig, ifield, am, i, n)
                bparnew = 0.0
             end if
          end do
       end do

       !Invert the matrix
       call init_inverse_matrix (am, i)

       !Free memory
       deallocate (am)

    end do

    call prof_leaving ("init_response_matrix", "fields_implicit")

  end subroutine init_response_matrix

  subroutine init_response_row (ig, ifield, am, ic, n)
    use fields_arrays, only: phi, apar, bpar, phinew, aparnew, bparnew
    use theta_grid, only: ntgrid
    use kt_grids, only: naky, ntheta0
    use dist_fn, only: getfieldeq, timeadv, M_class, N_class
    use run_parameters, only: fphi, fapar, fbpar
    use gs2_layouts, only: f_lo, idx, idx_local
    use prof, only: prof_entering, prof_leaving
    implicit none
    integer, intent (in) :: ig, ifield, ic, n
    complex, dimension(:,f_lo(ic)%llim_proc:), intent (in out) :: am
    complex, dimension (:,:,:), allocatable :: fieldeq, fieldeqa, fieldeqp
    integer :: irow, istart, iflo, ik, it, ifin, m, nn

    !For profiling
    call prof_entering ("init_response_row", "fields_implicit")

    !Always the same size so why bother doing this each time?
    allocate (fieldeq (-ntgrid:ntgrid, ntheta0, naky))
    allocate (fieldeqa(-ntgrid:ntgrid, ntheta0, naky))
    allocate (fieldeqp(-ntgrid:ntgrid, ntheta0, naky))

    !Find response to delta function fields
    !NOTE:Timeadv will loop over all iglo even though only one ik
    !has any amplitude, this is quite a waste. Should ideally do all
    !ik at once
    !NOTE:We currently do each independent supercell of the same length
    !together, this may not be so easy if we do all the ik together but it should
    !be possible.
    call timeadv (phi, apar, bpar, phinew, aparnew, bparnew, 0)
    call getfieldeq (phinew, aparnew, bparnew, fieldeq, fieldeqa, fieldeqp)

    !Loop over 2pi domains / cells
    do nn = 1, N_class(ic)

       !Loop over members of the current class (separate supercells/connected domains)
       do m = 1, M_class(ic)

          !Get corresponding it and ik indices
          it = f_lo(ic)%it(m,nn)
          ik = f_lo(ic)%ik(m,nn)
       
          !Work out which row of the matrix we're looking at
          !corresponds to iindex, i.e. which of the nindex points in the
          !supercell we're looking at.
          irow = ifield + nfield*((ig+ntgrid) + (2*ntgrid+1)*(n-1))
          
          !Convert iindex and m to iflo index
          iflo = idx (f_lo(ic), irow, m)
          
          !If this is part of our local iflo range then store
          !the response data
          if (idx_local(f_lo(ic), iflo)) then
             !Where abouts in the supercell does this 2pi*nfield section start
             istart = 0 + nidx*(nn-1)
             
             if (fphi > epsilon(0.0)) then
                ifin = istart + nidx
                istart = istart + 1
                am(istart:ifin:nfield,iflo) = fieldeq(:,it,ik) 
             end if
             
             if (fapar > epsilon(0.0)) then
                ifin = istart + nidx
                istart = istart + 1
                am(istart:ifin:nfield,iflo) = fieldeqa(:,it,ik)
             end if
             
             if (fbpar > epsilon(0.0)) then
                ifin = istart + nidx
                istart = istart + 1
                am(istart:ifin:nfield,iflo) = fieldeqp(:,it,ik)
             end if
             
          end if
                    
       end do
    end do

    !Free memory
    deallocate (fieldeq, fieldeqa, fieldeqp)

    !For profiling
    call prof_leaving ("init_response_row", "fields_implicit")
  end subroutine init_response_row

  subroutine init_inverse_matrix (am, ic)
    use file_utils, only: error_unit
    use kt_grids, only: aky, akx
    use theta_grid, only: ntgrid
    use mp, only: broadcast, send, receive, iproc
    use gs2_layouts, only: f_lo, idx, idx_local, proc_id, jf_lo
    use gs2_layouts, only: if_idx, im_idx, in_idx, local_field_solve
    use gs2_layouts, only: ig_idx, ifield_idx, ij_idx, mj, dj
    use prof, only: prof_entering, prof_leaving
    use fields_arrays, only: aminv
    use dist_fn, only: i_class, M_class, N_class
    implicit none
    integer, intent (in) :: ic
    complex, dimension(:,f_lo(ic)%llim_proc:), intent (in out) :: am
    complex, dimension(:,:), allocatable :: a_inv, lhscol, rhsrow
    complex, dimension (:), allocatable :: am_tmp
    complex :: fac
    integer :: i, j, k, ik, it, m, n, nn, if, ig, jsc, jf, jg, jc
    integer :: irow, ilo, jlo, dc, iflo, ierr
    logical :: iskip, jskip

    call prof_entering ("init_inverse_matrix", "fields_implicit")
    
    allocate (lhscol (nidx*N_class(ic),M_class(ic)))
    allocate (rhsrow (nidx*N_class(ic),M_class(ic)))
   
    !This is the length of a supercell
    j = nidx*N_class(ic)

    !Create storage space
    allocate (a_inv(j,f_lo(ic)%llim_proc:f_lo(ic)%ulim_alloc))
    a_inv = 0.0
    
    !Set (ifield*ig,ilo) "diagonal" to 1?
    do ilo = f_lo(ic)%llim_proc, f_lo(ic)%ulim_proc
       a_inv(if_idx(f_lo(ic),ilo),ilo) = 1.0
    end do

    ! Gauss-Jordan elimination, leaving out internal points at multiples of ntgrid 
    ! for each supercell
    !Loop over parallel gridpoints in supercell
    do i = 1, nidx*N_class(ic)
       !iskip is true iff the theta grid point(ig) corresponding to i
       !is at the upper end of a 2pi domain/cell and is not the rightmost gridpoint
       iskip = N_class(ic) > 1 !Are the multiple cells => are there connections/boundaries
       iskip = i <= nidx*N_class(ic) - nfield .and. iskip !Are we not near the upper boundary of the supercell
       iskip = mod((i+nfield-1)/nfield, 2*ntgrid+1) == 0 .and. iskip !Are we at a theta grid point corresponding to the rightmost point of a 2pi domain
       iskip = i > nfield .and. iskip !Are we not at the lower boundary of the supercell
       if (iskip) cycle
 
       if (local_field_solve) then
          do m = 1, M_class(ic)
             ilo = idx(f_lo(ic),i,m)
             if (idx_local(f_lo(ic),ilo)) then
                lhscol(:,m) = am(:,ilo)
                rhsrow(:,m) = a_inv(:,ilo)
             end if
          end do
       else
          !Loop over classes (supercell lengths)
          do m = 1, M_class(ic)
             !Convert to f_lo index
             ilo = idx(f_lo(ic),i,m)
             !Is ilo on this proc?
             if (idx_local(f_lo(ic),ilo)) then
                !If so store column/row
                lhscol(:,m) = am(:,ilo)
                rhsrow(:,m) = a_inv(:,ilo)
             end if
             !Here we send lhscol and rhscol sections to all procs
             !from the one on which it is currently known
             !Can't do this outside m loop as proc_id depends on m
             !These broadcasts can be relatively expensive so local_field_solve
             !may be preferable
             call broadcast (lhscol(:,m), proc_id(f_lo(ic),ilo))
             call broadcast (rhsrow(:,m), proc_id(f_lo(ic),ilo))
          end do
          !All procs will have the same lhscol and rhsrow after this loop+broadcast
       end if

       !Loop over field compound dimension
       do jlo = f_lo(ic)%llim_proc, f_lo(ic)%ulim_proc
          !jskip is true similarly to iskip
          jskip = N_class(ic) > 1 !Are there any connections?
          jskip = ig_idx(f_lo(ic), jlo) == ntgrid .and. jskip !Are we at a theta grid point corresponding to the upper boundary?
          !Get 2pi domain/cell number out of total for this supercell
          n = in_idx(f_lo(ic),jlo)
          jskip = n < N_class(ic) .and. jskip !Are we not in the last cell (i.e. not at the rightmost grid point/upper end of supercell)?
          if (jskip) cycle  !Skip this point if appropriate

          !Now get m (class number)
          m = im_idx(f_lo(ic),jlo)

          !Convert class number and cell number to ik and it
          ik = f_lo(ic)%ik(m,n)
          it = f_lo(ic)%it(m,n)
          
          !Work out what the compound theta*field index is.
          irow = if_idx(f_lo(ic),jlo)

          !If ky or kx are not 0 (i.e. skip zonal 0,0 mode) then workout the array
          if (aky(ik) /= 0.0 .or. akx(it) /= 0.0) then
             !Get factor
             fac = am(i,jlo)/lhscol(i,m)

             !Store array element
             am(i,jlo) = fac

             !Store other elements
             am(:i-1,jlo) = am(:i-1,jlo) - lhscol(:i-1,m)*fac
             am(i+1:,jlo) = am(i+1:,jlo) - lhscol(i+1:,m)*fac
             !WOULD the above three commands be better written as
             !am(:,jlo)=am(:,jlo)-lhscol(:,m)*fac
             !am(i,jlo)=fac

             !Fill in a_inv
             if (irow == i) then
                a_inv(:,jlo) = a_inv(:,jlo)/lhscol(i,m)
             else
                a_inv(:,jlo) = a_inv(:,jlo) &
                     - rhsrow(:,m)*lhscol(irow,m)/lhscol(i,m)
             end if
          else
             a_inv(:,jlo) = 0.0
          end if
   
       end do
    end do

    !Free memory
    deallocate (lhscol, rhsrow)

! fill in skipped points for each field and supercell:
! Do not include internal ntgrid points in sum over supercell

    do i = 1, nidx*N_class(ic)
       !iskip is true iff the theta grid point(ig) corresponding to i
       !is at the upper end of a 2pi domain/cell and is not the rightmost gridpoint
       iskip = N_class(ic) > 1 !Are the multiple cells => are there connections/boundaries
       iskip = i <= nidx*N_class(ic) - nfield .and. iskip  !Are we not near the upper boundary of the supercell
       iskip = mod((i+nfield-1)/nfield, 2*ntgrid+1) == 0 .and. iskip !Are we at a theta grid point corresponding to the rightmost point of a 2pi domain
       iskip = i > nfield .and. iskip !Are we not at the lower boundary of the supercell
       !Zero out skipped points
       if (iskip) then
          a_inv(i,:) = 0
          cycle !Seems unnexessary
       end if
    end do
! Make response at internal ntgrid points identical to response
! at internal -ntgrid points:
    do jlo = f_lo(ic)%llim_world, f_lo(ic)%ulim_world
       !jskip is true similarly to iskip
       jskip = N_class(ic) > 1 !Are there any connections?
       jskip = ig_idx(f_lo(ic), jlo) == ntgrid .and. jskip  !Are we at a theta grid point corresponding to the upper boundary?
       jskip = in_idx(f_lo(ic), jlo) < N_class(ic) .and. jskip  !Are we not in the last cell (i.e. not at the rightmost grid point/upper end of supercell)?
       !If we previously skipped this point then we want to fill it in from the matched/connected point
       if (jskip) then
          !What is the index of the matched point?
          ilo = jlo + nfield
          !If we have ilo on this proc send it to...
          if (idx_local(f_lo(ic), ilo)) then
             !jlo on this proc
             if (idx_local(f_lo(ic), jlo)) then
                a_inv(:,jlo) = a_inv(:,ilo)
             !jlo on proc which has jlo
             else
                call send(a_inv(:,ilo), proc_id(f_lo(ic), jlo))
             endif
          else
             !If this proc has jlo then get ready to receive
             if (idx_local(f_lo(ic), jlo)) then
                call receive(a_inv(:,jlo), proc_id(f_lo(ic), ilo))
             end if
          end if
       end if
    end do
    !The send receives in the above loop should be able to function in a
    !non-blocking manner fairly easily, but probably don't cost that much
    !Would require WAITALL before doing am=a_inv line below

    !Update am
    am = a_inv

    !Free memory
    deallocate (a_inv)

! Re-sort this class of aminv for runtime application.  

    !Now allocate array to store matrices for each class
    if (.not.allocated(aminv)) allocate (aminv(i_class))

! only need this large array for particular values of jlo.
! To save space, count how many this is and only allocate
! required space:

    !Initialise counter
    dc = 0
! check all members of this class
    do ilo = f_lo(ic)%llim_world, f_lo(ic)%ulim_world

! find supercell coordinates
       !i.e. what is my class of supercell and which cell am I looking at
       m = im_idx(f_lo(ic), ilo)
       n = in_idx(f_lo(ic), ilo)

! find standard coordinates
       !Get theta, field, kx and ky indexes for current point
       ig = ig_idx(f_lo(ic), ilo)
       if = ifield_idx(f_lo(ic), ilo)
       ik = f_lo(ic)%ik(m,n)
       it = f_lo(ic)%it(m,n)

! translate to fast field coordinates
       jlo = ij_idx(jf_lo, ig, if, ik, it)
          
! Locate this jlo, count it, and save address
       !Is this point on this proc, if so increment counter
       if (idx_local(jf_lo,jlo)) then
! count it
          dc = dc + 1
! save dcell address
          dj(ic,jlo) = dc
! save supercell address
          mj(jlo) = m
       endif
          
    end do

! allocate dcells and supercells in this class on this PE:
    !Loop over "fast field" index
    do jlo = jf_lo%llim_proc, jf_lo%ulim_proc
          
       !Allocate store in this class, on this proc to store the jlo points
       if (.not.associated(aminv(ic)%dcell)) then
          allocate (aminv(ic)%dcell(dc))
       else
          !Just check the array is the correct size
          j = size(aminv(ic)%dcell)
          if (j /= dc) then
             ierr = error_unit()
             write(ierr,*) 'Error (1) in init_inverse_matrix: ',&
                  iproc,':',jlo,':',dc,':',j
          endif
       endif
       
       !Get the current "dcell" adress
       k = dj(ic,jlo)

       !No dcell should be 0 but this is a guard
       if (k > 0) then
          !How long is the supercell for this class?
          jc = nidx*N_class(ic)

          !Allocate storage for the supercell if required
          if (.not.associated(aminv(ic)%dcell(k)%supercell)) then
             allocate (aminv(ic)%dcell(k)%supercell(jc))
          else
             !Just check the array is the correct size
             j = size(aminv(ic)%dcell(k)%supercell)
             if (j /= jc) then
                ierr = error_unit()
                write(ierr,*) 'Error (2) in init_inverse_matrix: ', &
                     iproc,':',jlo,':',jc,':',j
             end if
          end if
       end if
    end do

! Now fill aminv for this class:

    !Allocate temporary supercell storage
    allocate (am_tmp(nidx*N_class(ic)))

    !Loop over all grid points
    do ilo = f_lo(ic)%llim_world, f_lo(ic)%ulim_world

       !Get supercell type (class) and cell index
       m = im_idx(f_lo(ic), ilo)
       n = in_idx(f_lo(ic), ilo)
       
       !Convert to theta,field,kx and ky indexes
       ig = ig_idx(f_lo(ic), ilo)
       if = ifield_idx(f_lo(ic), ilo)
       ik = f_lo(ic)%ik(m,n)
       it = f_lo(ic)%it(m,n)
       
       !Get fast field index
       iflo = ij_idx(jf_lo, ig, if, ik, it)
 
       !If this ilo is local then...
       if (idx_local(f_lo(ic),ilo)) then
          ! send the am data to...
          if (idx_local(jf_lo,iflo)) then
             !the local proc
             am_tmp = am(:,ilo)
          else
             !the remote proc
             call send(am(:,ilo), proc_id(jf_lo,iflo))
          endif
       else
          !Get ready to receive the data
          if (idx_local(jf_lo,iflo)) then
             call receive(am_tmp, proc_id(f_lo(ic),ilo))
          end if
       end if

       !If the fast field index is on this processor
       if (idx_local(jf_lo, iflo)) then
          !Get "dcell" adress
          dc = dj(ic,iflo)

          !Loop over supercell size
          do jlo = 0, nidx*N_class(ic)-1
             !Convert to cell/2pi domain index
             nn = in_idx(f_lo(ic), jlo)
             
             !Get theta grid point
             jg = ig_idx(f_lo(ic), jlo)
             !Get field index
             jf = ifield_idx(f_lo(ic), jlo)
             
             !Convert index
             jsc = ij_idx(f_lo(ic), jg, jf, nn) + 1

             !Store inverse matrix data in appropriate supercell position
             aminv(ic)%dcell(dc)%supercell(jsc) = am_tmp(jlo+1)
             
          end do
       end if
    end do

    !Free memory
    deallocate (am_tmp)

    !For profiling
    call prof_leaving ("init_inverse_matrix", "fields_implicit")
  end subroutine init_inverse_matrix

  subroutine finish_fields_layouts

    use dist_fn, only: N_class, i_class, itright, boundary
    use kt_grids, only: naky, ntheta0
    use gs2_layouts, only: f_lo, jf_lo, ij, ik_idx, it_idx
    implicit none
    integer :: i, m, n, ii, ik, it, itr, jflo

    call boundary(linked)
    if (linked) then

! Complication comes from having to order the supercells in each class
       do ii = 1, i_class
          m = 1
          do it = 1, ntheta0
             do ik = 1, naky
                call kt2ki (i, n, ik, it)
                ! If (ik, it) is in this class, continue:
                if (i == ii) then
                   ! Find left end of links
                   if (n == 1) then
                      f_lo(i)%ik(m,n) = ik
                      f_lo(i)%it(m,n) = it
                      itr = it
                      ! Follow links to the right
                      do n = 2, N_class(i)
                         itr = itright (ik, itr)
                         f_lo(i)%ik(m,n) = ik
                         f_lo(i)%it(m,n) = itr
                      end do
                      m = m + 1
                   end if
                end if
             end do
          end do
       end do
       
    ! initialize ij matrix
       
       do jflo = jf_lo%llim_proc, jf_lo%ulim_proc
          ik = ik_idx(jf_lo, jflo)
          it = it_idx(jf_lo, jflo)
          
          call kt2ki (ij(jflo), n, ik, it)
          
       end do

    else
       m = 0
       do it = 1, ntheta0
          do ik = 1, naky
             m = m + 1
             f_lo(1)%ik(m,1) = ik
             f_lo(1)%it(m,1) = it
          end do
       end do
       
       ij = 1
    end if

  end subroutine finish_fields_layouts

  subroutine kt2ki (i, n, ik, it)

    use file_utils, only: error_unit
    use dist_fn, only: l_links, r_links, N_class, i_class

    integer, intent (in) :: ik, it
    integer, intent (out) :: i, n

    integer :: nn, ierr
!
! Get size of this supercell
!
    nn = 1 + l_links(ik,it) + r_links(ik,it)
!
! Find i = N_class**-1(nn)
!
    do i = 1, i_class
       if (N_class(i) == nn) exit
    end do
!
! Consistency check:
!
    if (N_class(i) /= nn) then
       ierr = error_unit()
       write(ierr,*) 'Error in kt2ki:'
       write(ierr,*) 'i = ',i,' ik = ',ik,' it = ',it,&
            ' N(i) = ',N_class(i),' nn = ',nn
       stop
    end if
! 
! Get position in this supercell, counting from the left
!
    n = 1 + l_links(ik, it)

  end subroutine kt2ki

  subroutine timer
    
    character (len=10) :: zdate, ztime, zzone
    integer, dimension(8) :: ival
    real, save :: told=0., tnew=0.
    
    call date_and_time (zdate, ztime, zzone, ival)
    tnew = ival(5)*3600.+ival(6)*60.+ival(7)+ival(8)/1000.
    if (told > 0.) then
       print *, 'Fields_implicit: Time since last called: ',tnew-told,' seconds'
    end if
    told = tnew
  end subroutine timer

end module fields_implicit

