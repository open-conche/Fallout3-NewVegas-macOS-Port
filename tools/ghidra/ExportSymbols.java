// Exports the precomputed symbol metadata consumed by ApplyMetadataAndDump.java from a fully
// analyzed program: functions.tsv, jumptables.tsv, noreturn.txt and metadata.json.
//
// Run after FixNoReturn + ResolveJumpTables + FixEntries (and optionally ResolveCrtOperationTables)
// on the -noanalysis pass so the program contains every recovered function and switch target.
//
// Args: <out_dir> <sha256-of-executable>
//@category BYOG

import java.io.*;
import java.nio.file.*;
import java.util.*;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.*;
import ghidra.program.model.listing.*;
import ghidra.program.model.mem.*;
import ghidra.program.model.symbol.*;

public class ExportSymbols extends GhidraScript {

    private static final String[] NO_RETURN_NAMES = {
        "__CxxThrowException@8", "_abort", "__abort", "abort",
        "___report_gsfailure", "__report_gsfailure",
        "___crtExitProcess", "__crtExitProcess"
    };

    /** True when every instruction in the body is alignment filler (0xCC/HLT). */
    private boolean isPadding(Function f, Listing listing) {
        int count = 0;
        for (Instruction in : listing.getInstructions(f.getBody(), true)) {
            count++;
            String m = in.getMnemonicString();
            if (!m.equalsIgnoreCase("INT3") && !m.equalsIgnoreCase("INT")
                    && !m.equalsIgnoreCase("HLT")) return false;
        }
        return count > 0;
    }

    private boolean isNoReturnName(String name) {
        String n = name;
        int ns = n.lastIndexOf("::");
        if (ns >= 0) n = n.substring(ns + 2);
        for (String want : NO_RETURN_NAMES) if (n.equals(want)) return true;
        return false;
    }

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 2) throw new IllegalArgumentException("Expected <out_dir> <sha256>");
        File outDir = new File(args[0]);
        if (!outDir.isDirectory() && !outDir.mkdirs()) throw new IOException("Cannot create " + outDir);
        String sha = args[1].trim().toLowerCase();

        Listing listing = currentProgram.getListing();
        FunctionManager fm = currentProgram.getFunctionManager();
        MemoryBlock text = currentProgram.getMemory().getBlock(".text");

        TreeMap<Long, String> functions = new TreeMap<>();
        for (Function f : fm.getFunctions(true)) {
            if (f.isExternal()) continue;
            Address e = f.getEntryPoint();
            if (e == null || e.isExternalAddress()) continue;
            if (f.getBody().getNumAddresses() == 0) continue;
            if (isPadding(f, listing)) continue;
            String name = f.getName();
            if (name == null || name.isEmpty()) name = String.format("FUN_%08x", e.getOffset());
            functions.put(e.getOffset(), name.replace('\t', ' ').replace('\n', ' '));
        }
        try (PrintWriter w = new PrintWriter(new OutputStreamWriter(
                new FileOutputStream(new File(outDir, "functions.tsv")), "UTF-8"))) {
            w.print("entry\tname\n");
            for (Map.Entry<Long, String> e : functions.entrySet())
                w.printf("%08x\t%s%n", e.getKey(), e.getValue());
        }

        TreeMap<Long, List<Long>> jumptables = new TreeMap<>();
        for (Instruction in : listing.getInstructions(true)) {
            if (text == null || !text.contains(in.getAddress())) continue;
            FlowType ft = in.getFlowType();
            if (!ft.isJump() || !ft.isComputed() || ft.isCall()) continue;
            LinkedHashSet<Long> targets = new LinkedHashSet<>();
            for (Reference r : in.getReferencesFrom()) {
                if (!r.getReferenceType().isFlow()) continue;
                Address t = r.getToAddress();
                if (text == null || !text.contains(t)) continue;
                if (listing.getInstructionAt(t) == null) continue;
                targets.add(t.getOffset());
            }
            if (!targets.isEmpty()) jumptables.put(in.getAddress().getOffset(), new ArrayList<>(targets));
        }
        try (PrintWriter w = new PrintWriter(new OutputStreamWriter(
                new FileOutputStream(new File(outDir, "jumptables.tsv")), "UTF-8"))) {
            w.print("jmp\ttargets\n");
            for (Map.Entry<Long, List<Long>> e : jumptables.entrySet()) {
                StringBuilder sb = new StringBuilder();
                for (Long t : e.getValue()) {
                    if (sb.length() > 0) sb.append(',');
                    sb.append(String.format("%08x", t));
                }
                w.printf("%08x\t%s%n", e.getKey(), sb);
            }
        }

        TreeMap<Long, String> noReturn = new TreeMap<>();
        for (Function f : fm.getFunctions(true)) {
            if (f.isExternal() || f.getEntryPoint() == null) continue;
            if (isNoReturnName(f.getName())) noReturn.put(f.getEntryPoint().getOffset(), f.getName());
        }
        try (PrintWriter w = new PrintWriter(new OutputStreamWriter(
                new FileOutputStream(new File(outDir, "noreturn.txt")), "UTF-8"))) {
            w.print("# Verified non-returning CRT routines\n");
            for (Map.Entry<Long, String> e : noReturn.entrySet())
                w.printf("%08x %s%n", e.getKey(), e.getValue());
        }

        int extraParents = 0;
        File extra = new File(outDir, "extra_entries.json");
        if (extra.isFile()) {
            String json = new String(Files.readAllBytes(extra.toPath()), "UTF-8");
            int i = 0;
            while ((i = json.indexOf("\":", i)) >= 0) {
                int start = i - 1;
                while (start >= 0 && Character.isDigit(json.charAt(start))) start--;
                if (start < i - 1) extraParents++;
                i += 2;
            }
        }

        try (PrintWriter w = new PrintWriter(new OutputStreamWriter(
                new FileOutputStream(new File(outDir, "metadata.json")), "UTF-8"))) {
            w.printf("{%n");
            w.printf("  \"sha256\": \"%s\",%n", sha);
            w.printf("  \"functions\": %d,%n", functions.size());
            w.printf("  \"jumptables\": %d,%n", jumptables.size());
            w.printf("  \"extra_parents\": %d%n", extraParents);
            w.printf("}%n");
        }

        println(String.format("ExportSymbols: %d functions, %d jump tables, %d noreturn, %d extra parents -> %s",
                functions.size(), jumptables.size(), noReturn.size(), extraParents, outDir));
    }
}
