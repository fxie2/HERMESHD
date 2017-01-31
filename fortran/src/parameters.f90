module parameters

    use input

    use lib_vtk_io
    use MKL_VSL_TYPE
    use MKL_VSL

    include '/nfs/packages/opt/Linux_x86_64/openmpi/1.6.3/intel13.0/include/mpif.h'

    integer, parameter :: rh=1, mx=2, my=3, mz=4, en=5
    integer, parameter :: pxx=6, pyy=7, pzz=8, pxy=9, pxz=10, pyz=11, nQ=11

    !===========================================================================
    ! Spatial resolution -- # grid cells and DG basis order
    !---------------------------------------------------------------------------
    ! The jump in accuracy b/w the linear basis (nbasis=4) and quadratic basis
    ! (nbasis=10) is much greater than jump b/w quadratic and cubic (nbasis=20).
    !   nbasis = 4:  {1,x,y,z}
    !   nbasis = 10: nbasis4  + {P_2(x),P_2(y),P_2(z), yz, zx, xy}
    !   nbasis = 20: nbasis10 + {xyz,xP2(y),yP2(x),xP2(z),
    !                                zP2(x),yP2(z),zP2(y),P3(x),P3(y),P3(z)}
    integer, parameter :: nbasis=8, nbastot=27

    ! For VTK output
    integer, parameter :: ngu=0

    ! iquad: # of Gaussian quadrature points per direction. iquad should not be:
    !   < ipoly (max Legendre polynomial order used) --> unstable
    !   > ipoly+1 --> an exact Gaussian quadrature for Legendre poly used
    ! Thus there are only two cases of iquad for a given nbasis. Both give similar
    ! results although iquad = ipoly + 1 is formally more accurate.
    integer, parameter :: nedge=iquad
    ! nface: number of quadrature points per cell face.
    ! npg: number of internal points per cell.
    integer, parameter :: nface=iquad*iquad, npg=nface*iquad, nfe=2*nface
    integer, parameter :: npge=6*nface, nslim=npg+6*nface
    !---------------------------------------------------------------------------


    !===========================================================================
    ! Constants, and physical and numerical parameters
    !---------------------------------------------------------------------------
    ! Useful constants
    real, parameter :: pi = 4.0*atan(1.0)
    real, parameter :: sqrt2 = 2.**0.5, sqrt2i = 1./sqrt2
    real, parameter :: c1d5 = 1./5., c1d3 = 1./3., c2d3 = 2./3., c4d3 = 4./3.

    ! Dimensional units -- expressed in MKS. NOTE: temperature (te0) in eV!
    real, parameter :: L0=1.0e-9, t0=1.0e-12, n0=3.32e28
        ! Derived units
        real, parameter :: v0 = L0/t0
        real, parameter :: p0 = mu*1.67e-27*n0*v0**2
        real, parameter :: te0=p0/n0/1.6e-19          ! NOTE: in eV (not K)!

    ! rh_min is a min density to be used for ideal gas EOS, rh_min is min density
    ! below which the pressure becomes negative for the MT water EOS.
    ! The DG-based subroutine "limiter" keeps density above rh_mult*rh_min.
    real, parameter :: rh_floor = 5.0e-6
    real, parameter :: T_floor = 0.026/te0
    real, parameter :: P_floor = T_floor*rh_floor
        ! Murnaghan-Tait EOS
        !   P = P_1*(density**7.2 - 1.) + P_base
        ! Note: the EOS for water is likely to be a critical player in getting the
        ! fluctuating hydrodynamics correct. There are much more sophisicated EOS's,
        ! some of which account for ionic solutions. Would be worthwhile to
        ! further investigate and experiment with different EOS's.
        real, parameter :: n_tm = 7.2  ! 7.2 (or 7.15) for water
        real, parameter :: P_1 = 2.15e9/n_tm/p0, P_base = 1.01e5/p0 ! atmo pressure
        real, parameter :: rh_mult = 1.01, rh_min = rh_mult*(1.0-P_base/P_1)**(1./n_tm)
    !---------------------------------------------------------------------------


    !===============================================================================
    !---------------------------------------------------------------------------
    ! NOTE: this is new stuff!
    ! Stuff for random matrix generation
    !---------------------------------------------------------------------------
    real, parameter :: nu = epsi*vis
    real, parameter :: c2d3nu=c2d3*nu, c4d3nu=c4d3*nu

    real, parameter :: T_base     = 300.0/1.16e4/te0  ! system temperature (for isothermal assumption)
    real, parameter :: eta_base   = vis    ! dynamic viscosity
    real, parameter :: zeta_base  = 0.  ! bulk viscosity---will need to adjust this!
    real, parameter :: kappa_base = 1.e-1

    real, parameter :: eta_sd   = (2.*eta_base*T_base)**0.5  ! stdev of fluctuations for shear viscosity terms
    real, parameter :: zeta_sd  = (zeta_base*T_base/3.)**0.5  ! stdev of fluctuations for bulk viscosity term
    real, parameter :: kappa_sd = (2.*kappa_base*T_base**2)**0.5

    real vsl_errcode
    TYPE (VSL_STREAM_STATE) :: vsl_stream

    integer, parameter :: vsl_brng   = VSL_BRNG_MCG31
    integer, parameter :: vsl_method = VSL_RNG_METHOD_GAUSSIAN_BOXMULLER
    real, parameter :: vsl_mean  = 0.0
    real, parameter :: vsl_sigma = 1.0
    !===============================================================================


    !===========================================================================
    ! Masking parameters (for advanced or internal initial/boundary conditions)
    !---------------------------------------------------------------------------
    logical MMask(nx,ny,nz),BMask(nx,ny,nz)
    !---------------------------------------------------------------------------

    !===========================================================================
    ! Parameters relating to quadratures and basis functions
    !---------------------------------------------------------------------------
    real wgt1d(5), wgt2d(30), wgt3d(100), cbasis(nbastot)
    ! wgt1d: quadrature weights for 1-D integration
    ! wgt2d: quadrature weights for 2-D integration
    ! wgt3d: quadrature weights for 3-D integration

    real, dimension(nface,nbastot) :: bfvals_zp, bfvals_zm
    real, dimension(nface,nbastot) :: bfvals_yp, bfvals_ym
    real, dimension(nface,nbastot) :: bfvals_xp, bfvals_xm
    real bf_faces(nslim,nbastot), bfvals_int(npg,nbastot),xquad(20)
        real bval_int_wgt(npg,nbastot)
        real wgtbfvals_xp(nface,nbastot),wgtbfvals_xm(nface,nbastot)  ! these are temps used to assign other vars
        real wgtbfvals_yp(nface,nbastot),wgtbfvals_ym(nface,nbastot)  ! these are temps used to assign other vars
        real wgtbfvals_zp(nface,nbastot),wgtbfvals_zm(nface,nbastot)  ! these are temps used to assign other vars
        real wgtbf_xmp(nface,2,nbastot),wgtbf_ymp(nface,2,nbastot),wgtbf_zmp(nface,2,nbastot)
        real sumx,sumy,sumz

        ! Basis function flags
        integer, parameter :: kx=2,ky=3,kz=4,kyz=5,kzx=6,kxy=7,kxyz=8
        integer, parameter :: kxx=9,kyy=10,kzz=11
        integer, parameter :: kyzz=12,kzxx=13,kxyy=14,kyyz=15,kzzx=16,kxxy=17
        integer, parameter :: kyyzz=18,kzzxx=19,kxxyy=20,kyzxx=21,kzxyy=22,kxyzz=23
        integer, parameter :: kxyyzz=24,kyzzxx=25,kzxxyy=26,kxxyyzz=27
    !---------------------------------------------------------------------------

    !===========================================================================
    ! VTK output parameters
    !---------------------------------------------------------------------------
    integer, parameter :: nvtk=1 ! was 2
    integer, parameter :: nvtk2=nvtk*nvtk, nvtk3=nvtk*nvtk*nvtk
    real, dimension(nvtk3,nbastot) :: bfvtk, bfvtk_dx, bfvtk_dy, bfvtk_dz
    real dxvtk,dyvtk,dzvtk
    !---------------------------------------------------------------------------

    !===========================================================================
    ! MPI definitions
    !---------------------------------------------------------------------------
    !   print_mpi is sets the MPI rank that will do any printing to console
    integer dims(3),coords(3),periods(3),nbrs(6),reqs(4),stats(MPI_STATUS_SIZE,4)
    integer,parameter:: NORTH=1,SOUTH=2,EAST=3,WEST=4,UP=5,DOWN=6,MPI_TT=MPI_REAL4
    !---------------------------------------------------------------------------

    real cflm


end module parameters