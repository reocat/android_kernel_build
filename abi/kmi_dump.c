
#include <elf.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>
#include <sys/errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/fcntl.h>
#include <sys/mman.h>

//  Dump symbols in the __KMI_DEFINE section of a 64 bit ARM64 little-endian
//  object (.o) file.  Assumes the computer where this program runs is little-
//  endian too.  There is no value in "generalizing" this code to run on big-
//  endian host and/or target big-endian ARM64, its not worth the noise that
//  that would add to the code.  The last big-endian architectures that matter
//  are IBM POWER and zSeries, the first one, when running Linux (at Google) is
//  run little-endian too.  We don't care about big endian POWER or zSeries.

typedef Elf64_Ehdr	header_t;
typedef Elf64_Shdr	section_t;
typedef Elf64_Sym	symbol_t;
typedef Elf64_Rela	rela_t;

typedef Elf64_Addr	adr_t;
typedef Elf64_Off	ofs_t;

typedef Elf64_Half	u16_t;
typedef Elf64_Word	u32_t;
typedef Elf64_Sword	s32_t;
typedef Elf64_Xword	u64_t;
typedef Elf64_Sxword	s64_t;

const char *cmd;
const char *file;
bool kmi_dump_debug = false;
bool kmi_dump_reloc = false;

#define KMI_V_PREFIX 		"__kmi_v_"
#define	KMI_V_PREFIX_LEN	8

void usage()
{
	fprintf(stderr, "usage: %s [-e] file.o\n"
			"\n"
			"Dumps values of symbols in KMI_DEFINE section in\n"
			"colon table format or with -e as enum declarations.\n",
		cmd);
	exit(1);
}

void errexit(const char *msg)
{
	if (file)
		fprintf(stderr, "%s: %s: %s\n", cmd, file, msg);
	else
		fprintf(stderr, "%s: %s\n", cmd, msg);
	exit(1);
}

void pexit(const char *msg)
{
	int error = errno;
	const char *errstr = strerror(error);
	if (!errstr)
		errexit(msg);
	if (file)
		fprintf(stderr, "%s: %s: %s: %s\n", cmd, file, msg, errstr);
	else
		fprintf(stderr, "%s: %s: %s\n", cmd, msg, errstr);
	exit(1);
}

void ptr_print(adr_t adr, const char *name)
{
	printf("%-16s 0x%016lx\n", name, adr);
}

void ofs_print(ofs_t ofs, const char *name)
{
	printf("%-16s 0x%016lx\n", name, ofs);
}

void u16_print(u16_t v, const char *name)
{
	printf("%-16s 0x%04x\n", name, v);
}

void u32_print(u32_t v, const char *name)
{
	printf("%-16s 0x%08x\n", name, v);
}

void u64_print(u64_t v, const char *name)
{
	printf("%-16s 0x%016lx\n", name, v);
}

void header_print(header_t *header)
{
	u16_print(header->e_type,      "e_type");
	u16_print(header->e_machine,   "e_machine");
	u32_print(header->e_version,   "e_version");
	ptr_print(header->e_entry,     "e_entry");
	ofs_print(header->e_phoff,     "e_phoff");
	ofs_print(header->e_shoff,     "e_shoff");
	u32_print(header->e_flags,     "e_flags");
	u16_print(header->e_ehsize,    "e_ehsize");
	u16_print(header->e_phentsize, "e_phentsize");
	u16_print(header->e_phnum,     "e_phnum");
	u16_print(header->e_shentsize, "e_shentsize");
	u16_print(header->e_shnum,     "e_shnum");
	u16_print(header->e_shstrndx,  "e_shstrndx");
}

void header_validate(header_t *header, size_t length)
{
	if (header->e_ident[EI_MAG0] != ELFMAG0 ||
	    header->e_ident[EI_MAG1] != ELFMAG1 ||
	    header->e_ident[EI_MAG2] != ELFMAG2 ||
	    header->e_ident[EI_MAG3] != ELFMAG3)
		errexit("not an ELF file");
	if (header->e_ident[EI_VERSION] != EV_CURRENT)
		errexit("invalid ELF file version");
	if (header->e_ident[EI_OSABI] != ELFOSABI_SYSV)
		errexit("invalid ELF file ABI");
	if (header->e_ident[EI_CLASS] != ELFCLASS64)
		errexit("ELF file is not a 64 bit ELF file");
	if (header->e_ident[EI_DATA] != ELFDATA2LSB) 
		errexit("ELF file is not a little-endian ELF file");
	if (header->e_machine != EM_AARCH64)
		errexit("ELF file is not an ARM AARCH64 ELF file");
	if (header->e_type != ET_REL)
		errexit("ELF file is not a relocatable file");
	if (header->e_phoff != 0 || header->e_phnum != 0)
		errexit("program headers must not be present in .o ELF file");
	if (header->e_shoff == 0 || header->e_shnum == 0)
		errexit("section headers must be present in .o ELF file");
	if (header->e_shentsize != sizeof(section_t))
		errexit("section header size is the wrong size");

	ofs_t shoff = header->e_shoff;
	ofs_t shoffend = shoff + header->e_shnum * sizeof(section_t);
	if (shoff < sizeof(header_t))
		errexit("section header table overlaps with ELF header");
	if (shoff >= shoffend)
		errexit("section header table end arithmetic overflow");
	if (shoffend > length)
		errexit("section header table outside of file");
	if (header->e_shstrndx >= header->e_shnum)
		errexit("string section header index outside section table");
}

char *section_name(section_t *section, section_t *shstrtab, void *map)
{
	char *str = (char *) map + shstrtab->sh_offset;
	return str + section->sh_name;
}

void section_print(section_t *section, section_t *shstrtab, void *map, int i)
{
	char *name = section_name(section, shstrtab, map);
	printf("section: %s (0x%x)\n", name, i);

	u32_print(section->sh_name,      "sh_name");
	u32_print(section->sh_type,      "sh_type");
	u64_print(section->sh_flags,     "sh_flags");
	ptr_print(section->sh_addr,      "sh_addr");
	ofs_print(section->sh_offset,    "sh_offset");
	u64_print(section->sh_size,      "sh_size");
	u32_print(section->sh_link,      "sh_link");
	u32_print(section->sh_info,      "sh_info");
	u64_print(section->sh_addralign, "sh_addralign");
	u64_print(section->sh_entsize,   "sh_entsize");
}

void section_validate(section_t *section, size_t length,
		      section_t *shstrtab, u32_t shnum)
{
	if (section->sh_addr != 0)
		errexit("relocatable file sections should not have an address");
	u64_t size = section->sh_size;
	ofs_t ofs = section->sh_offset;
	ofs_t ofsend = ofs + size;
	if (ofs == 0 && size != 0)
		errexit("non-empty section at beginning of file");
	if (ofs > ofsend)
		errexit("arithmetic overflow computing end of section data");

	//  Only sections with no data in the file are allowed to have an
	//  ofsend > lengh (i.e. be "outside" of the file, e.g. .bss sections)

	if (ofsend > length && section->sh_type != SHT_NOBITS)
		errexit("section data outside of file");
	if (section->sh_name >= shstrtab->sh_size)
		errexit("section name outside string section");
	if (section->sh_link >= shnum)
		errexit("invalid sh_link");
	if (section->sh_flags & SHF_INFO_LINK && section->sh_info >= shnum)
		errexit("invalid sh_info link");
	if (section->sh_flags & SHF_COMPRESSED)
		errexit("compressed section data not supported");
}

void strtab_validate(section_t *strtab, void *map)
{
	if (strtab->sh_size == 0)
		errexit("string table is empty");
	char *str = (char *) map + strtab->sh_offset;
	char *strend = str + strtab->sh_size;
	if (*strend != '\0')
		errexit("string table is not nul terminated");
}

void name_validate(section_t *strtab, u32_t name)
{
	if (name >= strtab->sh_size)
		errexit("string for name outside of string section");
}

void data_validate(section_t *section, adr_t value, u64_t size)
{
	adr_t valueend = value + size;
	if (value > valueend)
		errexit("overflow computing end location of value in section");
	if (valueend > section->sh_size)
		errexit("value outside of section");
}

void symtab_validate(section_t *symtab, size_t length,
		     section_t *strtab, u32_t shnum,
		     section_t *section_table, void *map)
{
	if (symtab->sh_entsize != sizeof(symbol_t))
		errexit("invalid symbol table entry size");

	size_t n = symtab->sh_size;
	if (n % sizeof(symbol_t) != 0)
		errexit("symbol table size not a multiple of symbol size");
	n /= sizeof(symbol_t);

	bool dummy_section_0 = section_table->sh_size == 0;
	symbol_t *symbol = (symbol_t *)((uintptr_t) map + symtab->sh_offset);
	symbol_t *symbolend = symbol + n;
	for (symbol_t *s = symbol; s < symbolend; ++s) {
		u16_t shndx = s->st_shndx;
		if (s->st_value == 0 && s->st_size == 0 &&
		    s->st_shndx == 0 && dummy_section_0)
			continue;
		name_validate(strtab, s->st_name);
		if (shndx >= shnum) {
			if (shndx == SHN_ABS)
				continue;
			errexit("invalid section header index in symbol");
		}
		data_validate(section_table + shndx, s->st_value, s->st_size);
		// XXX: validate: st_info st_other
	}
}

int rela_cmp(rela_t *a, rela_t *b)
{
	if (a->r_offset < b->r_offset)
		return -1;
	if (a->r_offset > b->r_offset)
		return 1;
	return 0;
}

rela_t *relatab_alloc(section_t *relakmi, size_t *nrelatab, void *map)
{
	if (relakmi == NULL) {
		*nrelatab = 0;
		return NULL;
	}

	if (relakmi->sh_entsize != sizeof(rela_t))
		errexit("invalid reloc table entry size");

	size_t size = relakmi->sh_size;
	if (size % sizeof(rela_t) != 0)
		errexit("reloc table size not a multiple of reloc size");
	size_t n = size / sizeof(rela_t);
	*nrelatab = n;

	rela_t *relatab = (rela_t *) ((uintptr_t) map + relakmi->sh_offset);
	rela_t *r = relatab;
	rela_t *lastr = r + n - 1;
	rela_t *nextr = r + 1;

	bool sorted = true;
	for (; r < lastr; r = nextr) {
		if (r->r_offset > nextr->r_offset) {
			sorted = false;
			break;
		}
		nextr = r + 1;
	}

	if (sorted)
		return relatab;

	rela_t *allocrelatab = malloc(n * sizeof(rela_t));
	if (allocrelatab == NULL)
		pexit("malloc of relocation table");

	memcpy(allocrelatab, relatab, size);
	qsort(allocrelatab, n, sizeof(rela_t),
	      (int (*)(const void *, const void *)) rela_cmp);

	return allocrelatab;
}

void relatab_free(section_t *relakmi, rela_t *relatab, void *map)
{
	if (relakmi == NULL)
		return;

	rela_t *kmirelatab = (rela_t *) ((uintptr_t) map + relakmi->sh_offset);
	if (kmirelatab != relatab)
		free(relatab);
}

bool relatab_has_address(rela_t *relatab, size_t nr, adr_t adr)
{
	// do not assume that bsearch works on a zero entry NULL pointed table
	if (!relatab)
		return false;
	rela_t r = {.r_offset = adr};
	return bsearch(&r, relatab, nr, sizeof(rela_t), 
		       (int (*)(const void *, const void *)) rela_cmp) != NULL;
}

// isprint(2) and friends do not have an easy query for characters that can
// be encoded into C string literals through character escape sequences.
// This table encodes C character literals of the form '\c' as the value of 'c'
// Also indicates through the value 1 what characters stand for themselves,
// values greater than 1 indicate a character encodable through a C escape 
// sequence. Note that a double quote and a backslash inside a C string literal
// have to be escaped ('\"' and '\\') within a string literal.
//
// This is of course, ASCII dependent, but remember that even Linux on the
// IBM mainframe (zSeries) uses ASCII, not EBCDIC. Non ASCII based character
// sets are extinct.

unsigned char strlit_table[256] = {
	['\a'] = 'a',	// 007 bel
	['\b'] = 'b',	// 010 bs
	['\t'] = 't',	// 011 ht
	['\n'] = 'n',	// 012 nl
	['\v'] = 'v',	// 013 vt
	['\f'] = 'f',	// 014 np
	['\r'] = 'r',	// 015 cr
	['\e'] = 'e',	// 033 esc

	//  Removed from table below
	['"']='"',	// 34 double quote
	['\\']='\\',	// 92 backslash

	[32]=1,  [33]=1,  /* " */  [35]=1,  [36]=1,  [37]=1,  [38]=1,  [39]=1,
	[40]=1,  [41]=1,  [42]=1,  [43]=1,  [44]=1,  [45]=1,  [46]=1,  [47]=1,
	[48]=1,  [49]=1,  [50]=1,  [51]=1,  [52]=1,  [53]=1,  [54]=1,  [55]=1,
	[56]=1,  [57]=1,  [58]=1,  [59]=1,  [60]=1,  [61]=1,  [62]=1,  [63]=1,
	[64]=1,  [65]=1,  [66]=1,  [67]=1,  [68]=1,  [69]=1,  [70]=1,  [71]=1,
	[72]=1,  [73]=1,  [74]=1,  [75]=1,  [76]=1,  [77]=1,  [78]=1,  [79]=1,
	[80]=1,  [81]=1,  [82]=1,  [83]=1,  [84]=1,  [85]=1,  [86]=1,  [87]=1,
	[88]=1,  [89]=1,  [90]=1,  [91]=1,  /* \ */  [93]=1,  [94]=1,  [95]=1,
	[96]=1,  [97]=1,  [98]=1,  [99]=1,  [100]=1, [101]=1, [102]=1, [103]=1,
	[104]=1, [105]=1, [106]=1, [107]=1, [108]=1, [109]=1, [110]=1, [111]=1,
	[112]=1, [113]=1, [114]=1, [115]=1, [116]=1, [117]=1, [118]=1, [119]=1,
	[120]=1, [121]=1, [122]=1, [123]=1, [124]=1, [125]=1, [126]=1, 
};

#define	IS_STRING_LITERAL_CHAR(c)	(strlit_table[(c) & 0xff] != 0)
#define IS_ENCODED_CHAR(c)		((c) > 1)
#define	ENCODE_CHAR(c)			(strlit_table[(c) & 0xff])

typedef void (*print_t)(symbol_t *s, char *name, unsigned char *value);

void dump(section_t *kmi, section_t *relakmi, u32_t kmiix,
	  section_t *symtab, section_t *strtab, rela_t *relatab,
	  size_t nrelatab, print_t print, void *map)
{
	size_t n = symtab->sh_size / sizeof(symbol_t);
	symbol_t *symbol = (symbol_t *)((uintptr_t) map + symtab->sh_offset);
	symbol_t *symbolend = symbol + n;
	unsigned char *data = (unsigned char *) map + kmi->sh_offset;

	for (symbol_t *s = symbol; s < symbolend; ++s) {
		char *str = (char *) map + strtab->sh_offset;
		char *name = str + s->st_name;
		if (s->st_shndx != kmiix)
			continue;

		adr_t adr = s->st_value;
		if (!kmi_dump_reloc && relatab_has_address(relatab,
							   nrelatab, adr))
			continue;

		if (strncmp(name, KMI_V_PREFIX, KMI_V_PREFIX_LEN) != 0)
			continue;

		unsigned char *value = data + adr;
		name += KMI_V_PREFIX_LEN;
		print(s, name, value);
	}
}

void print_raw(symbol_t *symbol, char *name, unsigned char *value)
{
	printf("%s:%ld:", name, symbol->st_size);

	// if symbol->st_size is 0: lastp == p - 1, case 0 takes care of it
	unsigned char *p = value, *lastp = p + symbol->st_size - 1;

	switch (symbol->st_size) {
	case 0:
		printf(":\n");
		return;
	case 1:
		printf("0x%02x:", *(unsigned char *) value);
		break;
	case 2:
		printf("0x%04x:", *(u16_t *) value);
		break;
	case 4:
		printf("0x%08x:", *(u32_t *) value);
		break;
	case 8:
		printf("0x%016lx:", *(u64_t *) value);
		break;
	default:
		for (p = value; p <= lastp; ++p)
			printf("0x%02x%c", *p, p < lastp ? ',' : ':');
		break;
	}

	// at least one character, string literal must be nul terminated
	bool strlit = *lastp == '\0';
	if (strlit) {
		for (p = value; p < lastp; ++p)
			if (!IS_STRING_LITERAL_CHAR(*p)) {
				strlit = false;
				break;
			}
		if (strlit) {
			putchar('"');
			for (p = value; p < lastp; ++p) {
				unsigned char c = *p;
				char encoded_char = ENCODE_CHAR(c);
				if (c == '\0')
					encoded_char = '0';
				if (IS_ENCODED_CHAR(encoded_char)) {
					putchar('\\');
					putchar(encoded_char);
				} else  {
					putchar(c);
				}
			}
			putchar('"');
		}
	}
	putchar('\n');
}

void print_enum(symbol_t *symbol, char *name, unsigned char *value)
{
	printf("enum __kmi_%s_s { __kmi_%s_size = %ld };\n",
	       name, name, symbol->st_size);

	size_t size = symbol->st_size;
	unsigned char *p = value;

	switch (size) {
	case 0:
		return;
	case 1:
		printf("enum __kmi_%s_v { __kmi_%s_val = 0x%02x };\n",
		       name, name, *(unsigned char *) value);
		return;
	case 2:
		printf("enum __kmi_%s_v { __kmi_%s_val = 0x%04x };\n",
		       name, name, *(u16_t *) value);
		return;
	case 4:
		printf("enum __kmi_%s_v { __kmi_%s_val = 0x%08x };\n",
		       name, name, *(u32_t *) value);
		return;
	case 8:
		printf("enum __kmi_%s_v { __kmi_%s_val = 0x%016lx };\n",
		       name, name, *(u64_t *) value);
		return;
	}

	unsigned char *endp = p + size;
	int i = 0;
	for (p = value; p < endp; ++p, ++i)
		printf("enum __kmi_%s_v_%08x { __kmi_%s_val_%08x = 0x%02x };\n",
		       name, i, name, i, *p);
}

int main(int argc, char **argv)
{
	//  Easier to pass across intermediate scripts than a debug argument.
	kmi_dump_debug = getenv("KMI_DUMP_DEBUG") != NULL;
	kmi_dump_reloc = getenv("KMI_DUMP_RELOC") != NULL;
	char *arg0 = argv[0];
	char *slash = strrchr(arg0, '/');
	cmd = slash ? slash + 1 : arg0;

	print_t fp = print_raw;
	if (argc == 3) {
		if (strcmp(argv[1], "-e") != 0)
			usage();
		fp = print_enum;
		--argc;
		++argv;
	}
	if (argc != 2)
		usage();
	file = argv[1];
	int fd = open(file, O_RDONLY);
	if (fd < 0)
		pexit("open(2) failed");
	struct stat st;
	if (fstat(fd, &st) < 0)
		pexit("stat(2) failed");
	size_t length = st.st_size;
	void *map = mmap(NULL, length, PROT_READ, MAP_SHARED, fd, (off_t) 0);
	if (map == MAP_FAILED)
		pexit("mmap(2) failed");

	header_t *header = map;
	header_validate(header, length);
	if (kmi_dump_debug) {
		header_print(header);
		putchar('\n');
	}

	section_t *section = (section_t *)((uintptr_t) map + header->e_shoff);
	section_t *section_end = section + header->e_shnum;

	section_t *shstrtab = section + header->e_shstrndx;
	if (shstrtab->sh_type != SHT_STRTAB)
		errexit("section header string section has wrong type");

	section_validate(shstrtab, length, shstrtab, header->e_shnum);
	strtab_validate(shstrtab, map);

	section_t *kmi = NULL;
	section_t *relakmi = NULL;
	section_t *symtab = NULL;
	u32_t kmiix = 0;

	for (section_t *s = section; s < section_end; ++s) {
		section_validate(s, length, shstrtab, header->e_shnum);
		if (!strcmp(section_name(s, shstrtab, map), "KMI_DEFINE")){
			if (kmi)
				errexit("multiple KMI_DEFINE sections");
			kmi = s;
			kmiix = s - section;
		}
		if (!strcmp(section_name(s, shstrtab, map), ".relaKMI_DEFINE")){
			if (relakmi)
				errexit("multiple .relaKMI_DEFINE sections");
			relakmi = s;
		}
		if (s->sh_type == SHT_SYMTAB) {
			if (symtab)
				errexit("multiple symbol table sections");
			symtab = s;
		}
	}

	if (kmi_dump_debug) {
		int i = 0;
		for (section_t *s = section; s < section_end; ++s, ++i) {
			section_print(s, shstrtab, map, i);
			putchar('\n');
		}
	}

	if (!kmi)
		errexit("no KMI_DEFINE section");
	if (!symtab)
		errexit("no symbol table section");

	if (relakmi) {
		if (!(relakmi->sh_flags & SHF_INFO_LINK))
			errexit(".relaKMI_DEFINE not linked to KMI_DEFINE");
		if (kmiix != relakmi->sh_info)
			errexit(".relaKMI_DEFINE linked to wrong section");
	}
	if (kmi_dump_debug)
		printf("kmiix = 0x%x\n", kmiix);

	if (symtab->sh_link >= header->e_shnum)
		errexit("symbol table string section is missing");
	section_t *strtab = section + symtab->sh_link;
	if (strtab->sh_type != SHT_STRTAB)
		errexit("string section for symbol table has wrong type");

	symtab_validate(symtab, length, strtab, header->e_shnum, section, map);
	size_t nrelatab;
	rela_t *relatab = relatab_alloc(relakmi, &nrelatab, map);
	dump(kmi, relakmi, kmiix, symtab, strtab, relatab, nrelatab, fp, map);
	relatab_free(relakmi, relatab, map);
	if (fflush(stdout) == EOF)
		pexit("fflush(stdout) failed");

	exit(0);
}
