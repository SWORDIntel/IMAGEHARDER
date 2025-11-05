use image_harden::{decode_jpeg, decode_png, ImageHardenError};
use libseccomp_rs::{ScmpAction, ScmpFilterContext, ScmpSyscall};
use nix::sched::{clone, CloneFlags};
use nix::sys::wait::{waitpid, WaitStatus};
use std::env;
use std::fs::File;
use std::io::{Read, Write};
use std::os::unix::io::FromRawFd;
use std::path::Path;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 2 {
        eprintln!("Usage: {} <path_to_image>", args[0]);
        return;
    }

    let (read_fd, write_fd) = nix::unistd::pipe().unwrap();
    let mut read_pipe = unsafe { File::from_raw_fd(read_fd) };
    let mut write_pipe = unsafe { File::from_raw_fd(write_fd) };

    const STACK_SIZE: usize = 1024 * 1024;
    let mut stack = [0; STACK_SIZE];

    let child_pid = unsafe {
        clone(
            Box::new(|| child_process(&args[1], &mut write_pipe)),
            &mut stack,
            CloneFlags::CLONE_NEWPID | CloneFlags::CLONE_NEWNET | CloneFlags::CLONE_NEWNS,
            None,
        )
        .unwrap()
    };

    match waitpid(child_pid, None).unwrap() {
        WaitStatus::Exited(_, 0) => {
            let mut result_buf = String::new();
            read_pipe.read_to_string(&mut result_buf).unwrap();
            println!("Successfully decoded image with size: {}", result_buf);
        }
        _ => {
            eprintln!("Failed to decode image");
        }
    }
}

fn child_process(image_path: &str, write_pipe: &mut File) -> isize {
    apply_seccomp_filter().unwrap();
    match decode_image(image_path) {
        Ok(decoded_image_len) => {
            write_pipe
                .write_all(decoded_image_len.to_string().as_bytes())
                .unwrap();
            0
        }
        Err(e) => {
            eprintln!("Failed to decode image: {}", e);
            1
        }
    }
}

fn decode_image(image_path: &str) -> Result<usize, ImageHardenError> {
    let path = Path::new(image_path);
    let mut file = File::open(path)?;
    let mut buffer = Vec::new();
    file.read_to_end(&mut buffer)?;

    let result = match path.extension().and_then(|s| s.to_str()) {
        Some("png") => decode_png(&buffer),
        Some("jpg") | Some("jpeg") => decode_jpeg(&buffer),
        _ => {
            return Err(ImageHardenError::JpegError("Unsupported file type".to_string()));
        }
    };

    result.map(|data| data.len())
}

fn apply_seccomp_filter() -> Result<(), Box<dyn std::error::Error>> {
    let mut filter = ScmpFilterContext::new_filter(ScmpAction::KillProcess)?;

    filter.add_rule(ScmpAction::Allow, ScmpSyscall::read)?;
    filter.add_rule(ScmpAction::Allow, ScmpSyscall::write)?;
    filter.add_rule(ScmpAction::Allow, ScmpSyscall::open)?;
    filter.add_rule(ScmpAction::Allow, ScmpSyscall::close)?;
    filter.add_rule(ScmpAction::Allow, ScmpSyscall::brk)?;
    filter.add_rule(ScmpAction::Allow, ScmpSyscall::mmap)?;
    filter.add_rule(ScmpAction::Allow, ScmpSyscall::exit_group)?;

    filter.load()?;

    Ok(())
}
