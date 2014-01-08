
class Generator
	def initialize(type, dimsize)
		@dimsize = dimsize
		@type = type
		if dimsize==0
		  @dimension = ""
		else
			@dimension = ", dimension(#{([":"]*dimsize).join(",")}) "
		end
	end
	def procedure_name
		"create_and_write_variable_#{@type.gsub(' ', '_')}_#{@dimsize}"
	end
	def val_get
		"val(#{@dimsize.times.map{|i| "starts(#{i+1}):"}.join(",")})"
	end
	def function_string
		string = <<EOF
 subroutine #{procedure_name}(gnostics, variable_type, variable_name, dimension_list, variable_description, variable_units, val)
   use simpledataio 
   use simpledataio_write 
   use diagnostics_config, only: diagnostics_type
   type(diagnostics_type), intent(in) :: gnostics
   integer, intent(in) :: variable_type
   character(*), intent(in) :: variable_name
   character(*), intent(in) :: dimension_list
   character(*), intent(in) :: variable_description
   character(*), intent(in) :: variable_units
   #{@type}, intent(in)#{@dimension} :: val
 
   if (gnostics%create) then 
     call create_variable(gnostics%sfile, variable_type, variable_name, dimension_list, variable_description, variable_units)
   end if

   if (gnostics%create .or. .not. gnostics%wryte) return
   
   call write_variable(gnostics%sfile, variable_name, val)

 end subroutine #{procedure_name}
EOF
  end

end

generators = []
['real', 'integer', 'character'].each do |type| # , 'double precision'
	(0..6).each do |dimsize|
		generators.push Generator.new(type, dimsize)
	end
end

string = <<EOF

!> DO NOT EDIT THIS FILE
!! This file is automatically generated by generate_diagnostics_create_and_write

module diagnostics_create_and_write

interface create_and_write_variable
#{generators.map{|g| "  module procedure " + g.procedure_name}.join("\n")}
end interface create_and_write_variable

contains

#{generators.map{|g| g.function_string}.join("\n")}

end module diagnostics_create_and_write

EOF


puts string
