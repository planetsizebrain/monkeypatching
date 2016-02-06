// https://stackoverflow.com/questions/3662144/recursive-listing-of-all-files-matching-a-certain-filetype-in-groovy
def files = []
new File(project.build.directory).eachFileRecurse() { file ->
	def s = file.getPath()
	if (s.endsWith(".class")) {
		files << "**" + s.substring(s.lastIndexOf('/'))
	}
}

// https://stackoverflow.com/questions/21867095/setting-properties-in-maven-with-gmaven
// https://stackoverflow.com/questions/17425684/maven-change-properties-on-the-fly-runtime
project.properties['patched.files'] = files.join(",")